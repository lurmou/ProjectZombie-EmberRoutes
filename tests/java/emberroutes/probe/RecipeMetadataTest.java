package emberroutes.probe;

import zombie.scripting.entity.components.crafting.CraftRecipe;

/** Real engine enum/signatures; no recipe effects, world or NPC construction. */
public final class RecipeMetadataTest {
    public static void main(String[] args) throws Exception {
        if (!ProbeRuntime.recipeHasCallbacks(null)) throw new AssertionError("missing recipe must fail closed");
        if (!ProbeRuntime.recipeKey(null).isEmpty()) throw new AssertionError("missing recipe has no key");
        CraftRecipe plain=new CraftRecipe();
        if (ProbeRuntime.recipeHasCallbacks(plain)) throw new AssertionError("plain metadata has no callbacks");
        for (var expected:CraftRecipe.LuaCall.values()) {
            CraftRecipe hooked=new CraftRecipe() {
                @Override public boolean hasLuaCall(LuaCall call) { return call==expected; }
            };
            if (!ProbeRuntime.recipeHasCallbacks(hooked)) throw new AssertionError("callback missed: "+expected);
        }
        var constructor=zombie.scripting.entity.components.crafting.OutputScript.class.getDeclaredConstructor(
            CraftRecipe.class,zombie.entity.components.resources.ResourceType.class);
        constructor.setAccessible(true);
        var output=constructor.newInstance(plain,zombie.entity.components.resources.ResourceType.Item);
        var mapper=new zombie.entity.components.crafting.recipe.OutputMapper("fixed");
        mapper.setDefaultOutputEntree("Base.WoodenFork");
        var field=output.getClass().getDeclaredField("outputMapper"); field.setAccessible(true); field.set(output,mapper);
        plain.getOutputs().add(output);
        if (ProbeRuntime.recipeHasSpecialOutputs(plain)) throw new AssertionError("fixed output mapper must be accepted");
        mapper.addOutputEntree("Base.WoodenSpoon",new String[]{"Base.SmallHandle"});
        if (!ProbeRuntime.recipeHasSpecialOutputs(plain)) throw new AssertionError("conditional output must be rejected");
        System.out.println("PASS actual CraftRecipe callback enum/profile boundary; game effects NOT RUN");
    }
}
