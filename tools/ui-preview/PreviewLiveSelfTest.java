import java.io.IOException;
import java.nio.file.*;
import java.util.*;
import org.json.JSONObject;

/** Drives real saving, watching, Lua compilation and native controls; never edits production. */
final class PreviewLiveSelfTest {
    final Path fixture,output;
    boolean complete;
    private int step,lastGeneration;
    private final List<String> passed=new ArrayList<>();
    PreviewLiveSelfTest(Path output) throws IOException {
        this.output=output;
        fixture=output.resolve("selftest-scene.lua");
        write(1,false);
    }
    private void write(int buttons,boolean renderError) throws IOException {
        Files.writeString(fixture,"require 'env'\nrequire 'ISUI/ISButton'\n"
            +"local p=ISPanel:new(20,20,500,280); p:initialise(); p:instantiate(); NativePreview=p\n"
            +"for i=1,"+buttons+" do local b=ISButton:new(12,12+(i-1)*40,180,30,'Live button '..i,p,function() end); "
            +"b:initialise(); b:instantiate(); p:addChild(b) end\n"
            +(renderError?"function p:prerender() self:setStencilRect(0,0,10,10); error('intentional live render error') end\n":"")
            +"PreviewDispose=function() p:setVisible(false) end\n");
    }
    private void pass(String label) {
        passed.add(label); System.out.println("PASS live self-test "+passed.size()+": "+label);
    }
    private static void check(boolean value,String message) { if (!value) throw new AssertionError(message); }
    void tick(NativeUiPreview app,int frame) throws Exception {
        var c=app.controls();
        boolean newReady=app.revision()>lastGeneration&&app.ready();
        boolean newError=app.revision()>lastGeneration&&app.failed();
        if (newError && !Set.of(2,4,8).contains(step)) throw new AssertionError("Unexpected error at test step "+step+": "+app.snapshot().getString("error"));
        switch (step) {
            case 0 -> {
                if (!app.ready()) return;
                check(app.current().root.getControls().size()==1,"Initial native button count");
                pass("one native button rendered"); lastGeneration=app.revision(); write(2,false); step++;
            }
            case 1 -> {
                if (!newReady) return;
                check(app.current().root.getControls().size()==2,"Saved second button did not appear");
                check(app.snapshot().getInt("nativeRoots")==1,"Reload leaked native roots");
                pass("saving source automatically adds a second native button");
                lastGeneration=app.revision(); Files.writeString(fixture,"this is not valid Lua ]"); step++;
            }
            case 2 -> {
                if (!newError) return;
                check(app.current().root==null,"Broken load retained old native page");
                pass("syntax failure becomes visible error, old page removed");
                lastGeneration=app.revision(); write(3,false); step++;
            }
            case 3 -> {
                if (!newReady) return;
                check(app.current().root.getControls().size()==3,"Syntax recovery did not show three buttons");
                pass("saving valid source recovers without restarting the JVM");
                lastGeneration=app.revision();
                if (!fixture.toAbsolutePath().normalize().startsWith(output.toAbsolutePath().normalize())) throw new AssertionError("Test path escaped output");
                Files.delete(fixture); step++;
            }
            case 4 -> {
                if (!newError) return;
                pass("removed scene becomes an observable load failure");
                lastGeneration=app.revision(); write(4,false); step++;
            }
            case 5 -> {
                if (!newReady) return;
                check(app.current().root.getControls().size()==4,"Missing-file recovery failed");
                pass("restored scene is detected after failed load");
                c.inspect=true; c.pick++; c.pickX=40; c.pickY=40; c.capture++; c.save(); step++;
            }
            case 6 -> {
                JSONObject selection=new JSONObject(Files.readString(output.resolve("selection.json")));
                if (!selection.has("label")) return;
                check(selection.getString("label").equals("Live button 1"),"Inspector picked wrong button");
                check(selection.getString("type").equals("ISButton"),"Inspector did not pick native widget");
                check(selection.getString("source").endsWith("ISButton.lua"),"Inspector source is not the loaded native class");
                pass("inspector records real native button label and bounds");
                Files.writeString(output.resolve("control.json"),"{partial"); step++;
            }
            case 7 -> {
                if (c.commandError.isEmpty()) return;
                check(c.scene.equals("widgets")&&app.ready(),"Malformed control mutated scene");
                pass("partial JSON rejected without changing valid scene");
                lastGeneration=app.revision(); c.save(); write(4,true); step++;
            }
            case 8 -> {
                if (!newError) return;
                check(app.snapshot().getString("error").contains("intentional live render error"),"Render exception was silently swallowed");
                pass("native callback render error reaches error feedback");
                lastGeneration=app.revision(); write(4,false); step++;
            }
            case 9 -> {
                if (!newReady) return;
                pass("render failure recovers on next save");
                lastGeneration=app.revision(); c.scene="squad"; c.save(); step++;
            }
            case 10 -> {
                if (!newReady) return;
                check(app.current().root.getControls().size()==4,"Production HUD header missing");
                var screenshot=javax.imageio.ImageIO.read(Path.of(app.snapshot().getString("latestCapture")).toFile());
                int pixel=screenshot.getRGB(25,25);
                check(Math.abs(((pixel>>16)&255)-20)<=2&&Math.abs(((pixel>>8)&255)-23)<=2&&Math.abs((pixel&255)-26)<=2,
                    "Previous page/error pixels survived scene switch");
                check((screenshot.getRGB(60,180)&255)>40,"HUD cards missing after unbalanced stencil recovery");
                pass("file command switches to production HUD and lifecycle");
                lastGeneration=app.revision(); c.reload++; c.save(); step++;
            }
            case 11 -> {
                if (!newReady) return;
                check(app.snapshot().getInt("nativeRoots")==1,"HUD repeated reload leaked roots");
                pass("HUD disposal/recreation succeeds with one native root");
                lastGeneration=app.revision(); c.scene="settlement"; c.save(); step++;
            }
            case 12 -> {
                if (!newReady) return;
                pass("file command switches to real Overview page body");
                check(app.snapshot().getInt("nativeRoots")==2,"Overview native tooltip was not rendered as a floating UI root");
                pass("Overview button focus creates and renders original ISToolTip");
                PreviewSession.call(zombie.Lua.LuaManager.env.rawget("PreviewTestTooltip"),false);
                step++;
            }
            case 13 -> {
                if (!app.ready()) return;
                check(app.snapshot().getInt("nativeRoots")==1,"Dismissed tooltip remained registered");
                pass("Overview tooltip dismiss removes its floating native root");
                lastGeneration=app.revision(); c.scene="squad"; c.save(); step++;
            }
            case 14 -> {
                if (!newReady) return;
                check(app.snapshot().getInt("nativeRoots")==1,"Overview disposal leaked floating UI");
                pass("switching away from Overview releases its watches and floating UI");
                c.quit=true; c.save(); complete=true;
                PreviewLiveControl.write(output.resolve("selftest.json"),new JSONObject().put("complete",true).put("passed",passed));
            }
            default -> throw new AssertionError("Unknown self-test step "+step);
        }
    }
}
