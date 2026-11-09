import java.io.*;
import java.nio.*;
import java.nio.file.*;
import java.util.*;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import org.json.JSONObject;
import org.lwjgl.glfw.GLFW;
import org.lwjgl.glfw.GLFWKeyCallback;
import org.lwjgl.glfw.GLFWMouseButtonCallback;
import org.lwjgl.opengl.GL11;
import org.lwjglx.opengl.*;
import zombie.*;
import zombie.core.SpriteRenderer;
import zombie.core.opengl.RenderThread;
import zombie.core.textures.*;
import zombie.ui.*;

/** Dedicated native UI workbench. Never attaches to a game, world or save. */
public final class NativeUiPreview {
    private final Path repo,output;
    private final int width,height,seconds;
    private final boolean live,smoke,injectFailure,selfTest;
    private final PreviewLiveControl control;
    private final PreviewInspector inspector=new PreviewInspector();
    private final ArrayDeque<Integer> keys=new ArrayDeque<>();
    private record MouseEvent(int action,int x,int y) {}
    private final ArrayDeque<MouseEvent> clicks=new ArrayDeque<>();
    private static final int[] TOOL_WIDTHS={66,66,66,78,70,56,82,78};
    private String[] toolLabels={"Native","Widgets","Squad","Overview","Reload","EN","Pick OFF","Capture"};
    private GLFWKeyCallback keyCallback,nativeKeyCallback;
    private GLFWMouseButtonCallback mouseCallback,nativeMouseCallback;
    private PreviewSession session;
    private PreviewLiveSelfTest test;
    private String loadedScene="",loadedLanguage="",error="",heading="",latest="";
    private List<String> errorLines=List.of();
    private int generation,generationFrames,captures,lastX,lastY;
    private long seenReload,seenCapture,seenPick,reloadMillis;
    private boolean showHelp=true,automaticCapture,captureRequested,toolDown;
    private Throwable reportedError;

    public static void main(String[] args) {
        int status=0;
        try { new NativeUiPreview(args).run(); }
        catch (Throwable failure) { failure.printStackTrace(); status=1; }
        System.exit(status); // PZ file-system workers are non-daemon; GL/UI are disposed first.
    }
    private NativeUiPreview(String[] args) throws Exception {
        output=Path.of(args[0]).toAbsolutePath(); repo=Path.of(args[5]).toAbsolutePath();
        smoke=Boolean.parseBoolean(args[2]); seconds=Integer.parseInt(args[3]);
        injectFailure=Boolean.parseBoolean(args[4]); width=Integer.parseInt(args[7]); height=Integer.parseInt(args[8]);
        live=Boolean.parseBoolean(args[9]); selfTest=Boolean.parseBoolean(args[10]);
        Files.createDirectories(output);
        String scene=Path.of(args[1]).getFileName().toString().replace("-scene.lua","");
        control=new PreviewLiveControl(output,scene,args[6]);
        if (selfTest) test=new PreviewLiveSelfTest(output);
    }
    private void run() throws Exception {
        ZomboidFileSystem.instance.setCacheDir(output.resolve("cache").toString());
        try {
            initializeRenderer();
            if (live) PreviewLiveControl.write(output.getParent().resolve("active.json"),
                new JSONObject().put("format",1).put("pid",ProcessHandle.current().pid())
                    .put("output",output.toString()).put("control",output.resolve("control.json").toString()));
            reload("initial");
            if (injectFailure) throw new IllegalStateException("Injected failure after native UI creation");
            long end=live?Long.MAX_VALUE:System.nanoTime()+seconds*1_000_000_000L;
            for (int frame=0;!Display.isCloseRequested()&&!control.quit&&System.nanoTime()<end;frame++) {
                Display.processMessages(); GameWindow.fileSystem.updateAsyncTransactions();
                boolean changed=control.pollCommand(); keyboard();
                if (!control.scene.equals(loadedScene)||!control.language.equals(loadedLanguage)||control.reload!=seenReload)
                    reload("command");
                else if ((live||selfTest)&&control.sourcesChanged(session,System.currentTimeMillis())) reload("source saved");
                if (changed) status();
                if (control.quit) break;
                mouse();
                if (!control.scene.equals(loadedScene)||!control.language.equals(loadedLanguage)||control.reload!=seenReload)
                    reload("toolbar");
                if (control.pick!=seenPick) {
                    seenPick=control.pick; inspector.pick(session,control.pickX,control.pickY); captureRequested=true; status();
                }
                if (generationFrames==1) waitForAssets();
                RenderThread.invokeOnRenderContext(this::drawFrame);
                generationFrames++;
                if (session!=null&&session.error!=null&&reportedError!=session.error) report(session.error,"render");
                if (selfTest) test.tick(this,frame);
                if (smoke&&!selfTest&&generationFrames>=4) break;
                Display.sync(30);
            }
            if (selfTest&&!test.complete) throw new IllegalStateException("Live self-test did not finish");
            if (smoke&&!error.isEmpty()) throw new IllegalStateException(error);
        } finally {
            try { if (session!=null) { session.close(); session=null; } }
            finally {
                if (Display.isCreated()) {
                    try {
                        RenderThread.invokeOnRenderContext(()->{
                            Set<zombie.core.fonts.AngelCodeFont> fonts=new HashSet<>();
                            Collections.addAll(fonts,TextManager.instance.enumToFont);
                            Collections.addAll(fonts,TextManager.instance.normal);
                            fonts.remove(null); for (var font:fonts) font.destroy();
                            TextureAssetManager.instance.destroy(); TextureIDAssetManager.instance.destroy();
                        });
                    } finally {
                        if (keyCallback!=null) { GLFW.glfwSetKeyCallback(Display.getWindow(),nativeKeyCallback); keyCallback.free(); }
                        if (mouseCallback!=null) { GLFW.glfwSetMouseButtonCallback(Display.getWindow(),nativeMouseCallback); mouseCallback.free(); }
                        Display.destroy();
                    }
                }
                PreviewLiveControl.write(output.resolve("closed.json"),new JSONObject().put("closed",true).put("generation",generation));
                System.out.println("CLEANUP display destroyed");
            }
        }
    }
    private void initializeRenderer() throws Exception {
        Display.init(); Display.setDisplayMode(new DisplayMode(width,height));
        Display.create(new PixelFormat(32,0,24,8,0));
        keyCallback=GLFWKeyCallback.create((window,key,scan,action,mods)->{
            if (action==GLFW.GLFW_PRESS) keys.add(key);
            if (nativeKeyCallback!=null) nativeKeyCallback.invoke(window,key,scan,action,mods);
        });
        nativeKeyCallback=GLFW.glfwSetKeyCallback(Display.getWindow(),keyCallback);
        mouseCallback=GLFWMouseButtonCallback.create((window,button,action,mods)->{
            if (button==0) {
                double[] x={0},y={0}; GLFW.glfwGetCursorPos(window,x,y);
                clicks.add(new MouseEvent(action,(int)x[0],(int)y[0]));
            }
            if (nativeMouseCallback!=null) nativeMouseCallback.invoke(window,button,action,mods);
        });
        nativeMouseCallback=GLFW.glfwSetMouseButtonCallback(Display.getWindow(),mouseCallback);
        System.out.println("GL "+GL11.glGetString(GL11.GL_VERSION));
        ZomboidFileSystem.instance.init();
        Path modDir = repo.resolve("Contents/mods/EmberRoutesProbe");
        ZomboidFileSystem.instance.setModIdToDir("EmberRoutesProbe", modDir.toString());
        try {
            var field = ZomboidFileSystem.class.getDeclaredField("modFolders");
            field.setAccessible(true);
            List<String> list = new ArrayList<>();
            list.add(modDir.toString());
            field.set(ZomboidFileSystem.instance, list);
            var lazyField = ZomboidFileSystem.class.getDeclaredField("allowedPrefixes");
            lazyField.setAccessible(true);
            ((zombie.util.ResettableLazyValue<?>) lazyField.get(ZomboidFileSystem.instance)).reset();
        } catch (Exception err) {
            err.printStackTrace();
        }
        ZomboidFileSystem.instance.loadMod("EmberRoutesProbe");
        TextureIDAssetManager.instance.create(TextureID.ASSET_TYPE,GameWindow.assetManagers);
        TextureAssetManager.instance.create(Texture.ASSET_TYPE,GameWindow.assetManagers);
        GameWindow.LoadTexturePack("UI", 2);
        GameWindow.LoadTexturePack("UI2", 2);
        GameWindow.LoadTexturePack("IconsMoveables", 2);
        GameWindow.setTexturePackLookup();
        zombie.core.VBO.GLVertexBufferObject.init(); zombie.core.Core.getInstance().initGlobalShader();
        Display.makeCurrent(); SpriteRenderer.instance.create();
        zombie.core.Core.getInstance().setScreenSize(width,height);
        zombie.core.Languages.instance.init();
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        zombie.SoundManager.instance=new zombie.DummySoundManager();
    }
    private void reload(String reason) throws Exception {
        long started=System.nanoTime();
        generation++; generationFrames=0; automaticCapture=true;
        inspector.clear(); clicks.clear();
        reportedError=null; error=""; errorLines=List.of();
        PreviewLiveControl.write(output.resolve("selection.json"),new JSONObject().put("format",1).put("generation",generation).put("state","cleared"));
        loadedScene=control.scene; seenReload=control.reload;
        try {
            if (session!=null) { session.close(); session=null; }
            if (!control.language.equals(loadedLanguage)) {
                zombie.core.Translator.setLanguage(zombie.core.Languages.instance.getByName(control.language));
                TextManager.instance.Init(); waitForAssets();
            }
            loadedLanguage=control.language;
            Path file=test!=null&&control.scene.equals("widgets")?test.fixture:repo.resolve("tools/ui-preview/"+control.scene+"-scene.lua");
            session=new PreviewSession(repo,output,file,generation);
            session.load(control.language,smoke);
            waitForAssets(); control.loaded(session,true);
            System.out.println("READY generation "+generation+" | "+control.scene+" | "+reason);
        } catch (Exception failure) {
            if (session!=null) control.loaded(session,false);
            report(failure,"load");
        }
        reloadMillis=(System.nanoTime()-started)/1_000_000;
        status();
    }
    private void keyboard() throws IOException {
        boolean changed=false;
        while (!keys.isEmpty()) {
            int key=keys.remove();
            if (key>=GLFW.GLFW_KEY_F1&&key<=GLFW.GLFW_KEY_F4) { control.scene=PreviewLiveControl.SCENES.get(key-GLFW.GLFW_KEY_F1); changed=true; }
            if (key==GLFW.GLFW_KEY_F5) { control.reload++; changed=true; }
            if (key==GLFW.GLFW_KEY_F6) { control.language=control.language.equals("CN")?"EN":"CN"; changed=true; }
            if (key==GLFW.GLFW_KEY_F7) showHelp=!showHelp;
            if (key==GLFW.GLFW_KEY_F8) { control.inspect=!control.inspect; changed=true; }
            if (key==GLFW.GLFW_KEY_F9) { control.capture++; changed=true; }
            if (key==GLFW.GLFW_KEY_ESCAPE) { control.quit=true; changed=true; }
        }
        if (changed) { control.save(); status(); }
    }
    private void mouse() throws IOException {
        zombie.input.Mouse.poll(); zombie.input.Mouse.update();
        int x=zombie.input.Mouse.getXA(),y=zombie.input.Mouse.getYA();
        UIElement root=session!=null&&session.root!=null&&session.error==null&&error.isEmpty()?session.root:null;
        if (root!=null) {
            if (!control.inspect) {
                root.onMouseMove(x-lastX,y-lastY);
                int wheel=zombie.input.Mouse.getWheelState();
                if (wheel!=0) root.onMouseWheel(wheel>0?-1:1);
            }
        }
        while (!clicks.isEmpty()) {
                MouseEvent event=clicks.remove();
                if (event.action==GLFW.GLFW_PRESS&&toolbar(event.x,event.y)) { toolDown=true; continue; }
                if (event.action==GLFW.GLFW_RELEASE&&toolDown) { toolDown=false; continue; }
                if (root==null) continue;
                if (control.inspect) {
                    if (event.action==GLFW.GLFW_PRESS) { inspector.pick(session,event.x,event.y); captureRequested=true; status(); }
                } else if (event.action==GLFW.GLFW_PRESS) root.onMouseDown(event.x-root.getX(),event.y-root.getY());
                else if (event.action==GLFW.GLFW_RELEASE) root.onMouseUp(event.x-root.getX(),event.y-root.getY());
        }
        clicks.clear(); lastX=x; lastY=y;
    }
    private boolean toolbar(int x,int y) throws IOException {
        if (!showHelp||y<height-36||y>=height-18) return false;
        int left=10;
        for (int i=0;i<TOOL_WIDTHS.length;i++) {
            if (x>=left&&x<left+TOOL_WIDTHS[i]) {
                if (i<4) control.scene=PreviewLiveControl.SCENES.get(i);
                else if (i==4) control.reload++;
                else if (i==5) control.language=control.language.equals("CN")?"EN":"CN";
                else if (i==6) control.inspect=!control.inspect;
                else control.capture++;
                control.save(); status(); return true;
            }
            left+=TOOL_WIDTHS[i]+4;
        }
        return false;
    }
    private void drawFrame() {
        GL11.glViewport(0,0,width,height); GL11.glClearColor(.08f,.09f,.10f,1);
        // Native UI leaves scissor/masks behind. Clear the entire window before a new frame.
        GL11.glDisable(GL11.GL_SCISSOR_TEST); GL11.glColorMask(true,true,true,true);
        GL11.glDisable(GL11.GL_STENCIL_TEST);
        GL11.glDepthMask(true); GL11.glStencilMask(255);
        GL11.glClear(GL11.GL_COLOR_BUFFER_BIT|GL11.GL_STENCIL_BUFFER_BIT);
        GL11.glEnable(GL11.GL_BLEND); GL11.glBlendFunc(GL11.GL_SRC_ALPHA,GL11.GL_ONE_MINUS_SRC_ALPHA);
        var r=SpriteRenderer.instance;
        r.prePopulating();
        PreviewFrame.resetStencilDepth();
        r.glDoStartFrame(width,height,1,-1); r.StartShader(zombie.core.SceneShaderStore.defaultShaderId,-1);
        if (error.isEmpty()&&session!=null) session.draw();
        else {
            TextManager.instance.DrawString(UIFont.Medium,24,24,"Preview load failed - fix the file, or press F5",1,.4,.3,1);
            for (int i=0;i<errorLines.size();i++) TextManager.instance.DrawString(UIFont.Small,24,60+i*20,errorLines.get(i),1,.8,.75,1);
        }
        if (control.inspect) inspector.draw();
        if (showHelp) {
            r.renderRect(0,height-54,width,54,.025f,.03f,.04f,.96f);
            TextManager.instance.DrawString(UIFont.Small,10,height-50,heading,.9,.9,.9,1);
            int left=10;
            for (int i=0;i<TOOL_WIDTHS.length;i++) {
                r.renderRect(left,height-36,TOOL_WIDTHS[i],18,.13f,.17f,.20f,1);
                TextManager.instance.DrawString(UIFont.Small,left+5,height-35,toolLabels[i],.8,.9,1,1);
                left+=TOOL_WIDTHS[i]+4;
            }
            TextManager.instance.DrawString(UIFont.Small,10,height-16,control.commandError.isEmpty()?inspector.caption:control.commandError,.95,.8,.35,1);
        }
        r.glDoEndFrame(); r.pushFrameDown(); r.acquireStateForRendering(()->false); r.postRender();
        int glError=GL11.glGetError();
        if (glError!=GL11.GL_NO_ERROR) throw new IllegalStateException("OpenGL error "+glError);
        if (automaticCapture&&generationFrames>=2) { capture("preview-r"+generation); automaticCapture=false; }
        if (control.capture!=seenCapture || captureRequested) {
            seenCapture=control.capture; captureRequested=false; capture("capture-"+(++captures));
        }
        Display.update();
    }
    private void capture(String name) {
        try {
            Path file=output.resolve(name+".png");
            ByteBuffer pixels=ByteBuffer.allocateDirect(width*height*4);
            GL11.glReadPixels(0,0,width,height,GL11.GL_RGBA,GL11.GL_UNSIGNED_BYTE,pixels);
            BufferedImage image=new BufferedImage(width,height,BufferedImage.TYPE_INT_ARGB);
            for (int y=0;y<height;y++) for (int x=0;x<width;x++) {
                int i=((height-1-y)*width+x)*4;
                image.setRGB(x,y,((pixels.get(i+3)&255)<<24)|((pixels.get(i)&255)<<16)|((pixels.get(i+1)&255)<<8)|(pixels.get(i+2)&255));
            }
            ImageIO.write(image,"png",file.toFile()); latest=file.toString();
            Path temporary=output.resolve("latest.png.tmp");
            Files.copy(file,temporary,StandardCopyOption.REPLACE_EXISTING);
            Files.move(temporary,output.resolve("latest.png"),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
            JSONObject metadata=snapshot();
            if (inspector.selection!=null) metadata.put("selection",inspector.selection);
            PreviewLiveControl.write(output.resolve(name+".json"),metadata);
            status(); System.out.println("CAPTURE "+file);
        } catch (IOException failure) { throw new UncheckedIOException(failure); }
    }
    private void report(Throwable failure,String phase) throws IOException {
        reportedError=failure; error=phase+": "+Objects.toString(failure.getMessage(),failure.getClass().getSimpleName());
        String text=error.replace('\r',' ').replace('\n',' ');
        List<String> lines=new ArrayList<>(); int limit=Math.max(30,(width-48)/7);
        for (int at=0;at<Math.min(text.length(),limit*12);at+=limit) lines.add(text.substring(at,Math.min(text.length(),at+limit)));
        errorLines=lines; automaticCapture=true;
        try (PrintWriter writer=new PrintWriter(Files.newBufferedWriter(output.resolve("error-r"+generation+".log")))) { failure.printStackTrace(writer); }
        System.err.println("ERROR generation "+generation+" "+text.substring(0,Math.min(250,text.length()))); status();
    }
    JSONObject snapshot() {
        return new JSONObject().put("format",1).put("pid",ProcessHandle.current().pid()).put("live",live)
            .put("generation",generation).put("scene",control.scene).put("language",control.language)
            .put("state",error.isEmpty()?"ready":"error").put("error",error).put("commandError",control.commandError)
            .put("reloadMillis",reloadMillis).put("width",width).put("height",height).put("inspect",control.inspect)
            .put("latestCapture",latest).put("sourceCount",session==null?0:session.sources.size())
            .put("nativeRoots",UIManager.getUI().size()).put("rootControls",session==null||session.root==null?0:session.root.getControls().size());
    }
    private void status() throws IOException {
        toolLabels=new String[]{"Native","Widgets","Squad","Overview","Reload",control.language,control.inspect?"Pick ON":"Pick OFF","Capture"};
        heading=control.scene+" | "+control.language+" | generation "+generation+" | "+(error.isEmpty()?"READY":"ERROR")
            +" | reload "+reloadMillis+"ms | "+(live?"watch ON":"bounded preview")+(control.inspect?" | PICK MODE":"")+" | synthetic business data";
        Display.setTitle("EmberRoutes UI | "+heading); PreviewLiveControl.write(output.resolve("status.json"),snapshot());
    }
    static void waitForAssets() throws Exception {
        long deadline=System.nanoTime()+20_000_000_000L;
        while (GameWindow.fileSystem.hasWork()||TextManager.instance.isAnyFontLoading()) {
            GameWindow.fileSystem.updateAsyncTransactions(); Display.processMessages();
            if (System.nanoTime()>deadline) throw new IllegalStateException("Asset load timed out");
            Thread.sleep(10);
        }
    }
    PreviewLiveControl controls() { return control; }
    PreviewSession current() { return session; }
    int revision() { return generation; }
    boolean ready() { return error.isEmpty()&&generationFrames>=3; }
    boolean failed() { return !error.isEmpty()&&generationFrames>=3; }
}
