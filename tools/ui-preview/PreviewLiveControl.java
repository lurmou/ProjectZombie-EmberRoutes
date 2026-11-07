import java.io.*;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.*;
import org.json.JSONObject;

/** File commands and bounded source polling. All files are in the owned run directory. */
final class PreviewLiveControl {
    static final List<String> SCENES=List.of("native","widgets","squad","settlement");
    record Stamp(boolean exists,long modified,long size) {
        static Stamp read(Path path) {
            try {
                var a=Files.readAttributes(path,BasicFileAttributes.class);
                return new Stamp(true,a.lastModifiedTime().toMillis(),a.size());
            } catch (NoSuchFileException missing) { return new Stamp(false,0,0); }
            catch (IOException failure) { throw new UncheckedIOException(failure); }
        }
    }
    final Path output;
    String scene,language,commandError="";
    boolean inspect,quit;
    long reload,capture,pick;
    int pickX,pickY;
    private Stamp controlStamp;
    private final Map<Path,Stamp> baseline=new LinkedHashMap<>();
    private Map<Path,Stamp> pending;
    private long nextPoll,pendingSince;

    PreviewLiveControl(Path output,String scene,String language) throws IOException {
        this.output=output; this.scene=scene; this.language=language; save();
    }
    JSONObject config() {
        return new JSONObject().put("format",1).put("scene",scene).put("language",language)
            .put("inspect",inspect).put("reload",reload).put("capture",capture).put("quit",quit)
            .put("pick",pick).put("pickX",pickX).put("pickY",pickY);
    }
    void save() throws IOException {
        commandError="";
        write(output.resolve("control.json"),config());
        controlStamp=Stamp.read(output.resolve("control.json"));
    }
    boolean pollCommand() {
        Path file=output.resolve("control.json"); Stamp stamp=Stamp.read(file);
        if (stamp.equals(controlStamp)) return false;
        controlStamp=stamp;
        try {
            JSONObject c=new JSONObject(Files.readString(file));
            String s=c.getString("scene"),l=c.getString("language");
            if (c.getInt("format")!=1 || !SCENES.contains(s) || !List.of("CN","EN").contains(l))
                throw new IllegalArgumentException("Unsupported control format/scene/language");
            // Validate the entire command before changing any effective configuration.
            boolean i=c.getBoolean("inspect"),q=c.getBoolean("quit");
            long r=c.getLong("reload"),p=c.getLong("capture"),k=c.getLong("pick");
            int x=c.getInt("pickX"),y=c.getInt("pickY");
            if (r<0 || p<0 || k<0) throw new IllegalArgumentException("Counters must be nonnegative");
            scene=s; language=l; inspect=i; quit=q; reload=r; capture=p; pick=k; pickX=x; pickY=y;
            commandError=""; return true;
        } catch (Exception failure) { commandError="Control rejected: "+failure.getMessage(); return true; }
    }
    void loaded(PreviewSession session,boolean success) {
        if (success) baseline.clear();
        else baseline.replaceAll((path,stamp)->Stamp.read(path));
        baseline.putAll(session.sources);
        pending=null;
    }
    boolean sourcesChanged(PreviewSession session,long now) {
        if (now<nextPoll) return false;
        nextPoll=now+250;
        if (session!=null) for (var item:session.sources.entrySet()) baseline.putIfAbsent(item.getKey(),item.getValue());
        Map<Path,Stamp> current=new LinkedHashMap<>();
        baseline.forEach((path,stamp)->current.put(path,Stamp.read(path)));
        if (current.equals(baseline)) { pending=null; return false; }
        if (!current.equals(pending)) { pending=current; pendingSince=now; return false; }
        return now-pendingSince>=250;
    }
    static void write(Path file,JSONObject data) throws IOException {
        Path temporary=file.resolveSibling(file.getFileName()+".tmp");
        Files.writeString(temporary,data.toString(2));
        Files.move(temporary,file,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
    }
}
