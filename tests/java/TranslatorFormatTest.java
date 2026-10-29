import java.nio.file.*;
import java.util.*;
import java.util.regex.*;
import zombie.core.Translator;

/** Installed Translator only; inject translation maps without starting the game. */
class TranslatorFormatTest {
    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        var field=Translator.class.getDeclaredField("igui"); field.setAccessible(true);
        var translations=(Map<String,String>)field.get(null);
        var normalize=Translator.class.getDeclaredMethod("formatFixer",String.class); normalize.setAccessible(true);
        var rows=Pattern.compile("\"(IGUI_EmberRoutesProbe_(?:Public_[^\"]+|Monitor_[^\"]+|Stock_[^\"]+|Crafting_(?:chainPlanHeading|stepFinal|stepPrecursor|planOutput)))\"\\s*:\\s*\"([^\"]*)\"");
        int checks=0;
        for (String lang:List.of("CN","EN")) {
            var file=Path.of("Contents/mods/EmberRoutesProbe/42/media/lua/shared/Translate",lang,"IG_UI.json");
            var matcher=rows.matcher(Files.readString(file));
            while(matcher.find()) {
                String key=matcher.group(1),raw=matcher.group(2);
                if(!raw.contains("%")) continue;
                if(raw.matches(".*%[ds].*")) throw new AssertionError("Legacy formatter: "+key);
                translations.put(key,(String)normalize.invoke(null,raw));
                Object[] values={"20","7","worker","recipe"};
                String expected=raw;
                for(int i=1;i<=values.length;i++) expected=expected.replace("%"+i,values[i-1].toString());
                String actual=Translator.getText(key,values);
                if(!expected.equals(actual)) throw new AssertionError(lang+" "+key+": "+actual);
                checks++;
            }
        }
        if(checks!=70) throw new AssertionError("Expected 70 translated formats, got "+checks);
        System.out.println("PASS "+checks+" installed Translator CN/EN parameter checks; game NOT RUN");
    }
}
