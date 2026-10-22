# 当前JAR制作关键方法字节码

> 2026-10-21｜状态：静态取证完成；未实机验证｜[核查结论](../commissioned-crafting-review.md)

来源：baseline.json所列当前安装JAR的javap -c -p，不来自旧反编译树。只读反汇编，不是执行验证。

## CraftRecipeManager-javap.txt public static boolean isValidRecipeForCharacter(zombie.scripting.entity.components.crafting.CraftRecipe, zombie.characters.IsoGameCharacter, zombie.entity.components.crafting.CraftRecipeMonitor, java.util.ArrayList<zombie.inventory.ItemContainer>);

```text
  public static boolean isValidRecipeForCharacter(zombie.scripting.entity.components.crafting.CraftRecipe, zombie.characters.IsoGameCharacter, zombie.entity.components.crafting.CraftRecipeMonitor, java.util.ArrayList<zombie.inventory.ItemContainer>);
    Code:
         0: aload_0
         1: ifnonnull     15
         4: getstatic     #345                // Field zombie/debug/DebugType.CraftLogic:Lzombie/debug/DebugType;
         7: ldc_w         #348                // String Recipe is null
        10: invokevirtual #350                // Method zombie/debug/DebugType.debugln:(Ljava/lang/Object;)V
        13: iconst_0
        14: ireturn
        15: aload_1
        16: ifnull        62
        19: aload_0
        20: aload_1
        21: aload_3
        22: invokestatic  #353                // Method validateHasRequiredSkill:(Lzombie/scripting/entity/components/crafting/CraftRecipe;Lzombie/characters/IsoGameCharacter;Ljava/util/ArrayList;)Z
        25: ifne          62
        28: aload_2
        29: ifnull        45
        32: aload_2
        33: aload_0
        34: invokevirtual #357                // Method zombie/scripting/entity/components/crafting/CraftRecipe.getScriptObjectFullType:()Ljava/lang/String;
        37: invokedynamic #360,  0            // InvokeDynamic #2:makeConcatWithConstants:(Ljava/lang/String;)Ljava/lang/String;
        42: invokevirtual #362                // Method zombie/entity/components/crafting/CraftRecipeMonitor.log:(Ljava/lang/String;)V
        45: getstatic     #345                // Field zombie/debug/DebugType.CraftLogic:Lzombie/debug/DebugType;
        48: aload_0
        49: invokevirtual #357                // Method zombie/scripting/entity/components/crafting/CraftRecipe.getScriptObjectFullType:()Ljava/lang/String;
        52: invokedynamic #360,  0            // InvokeDynamic #2:makeConcatWithConstants:(Ljava/lang/String;)Ljava/lang/String;
        57: invokevirtual #350                // Method zombie/debug/DebugType.debugln:(Ljava/lang/Object;)V
        60: iconst_0
        61: ireturn
        62: aload_1
        63: ifnull        116
        66: aload_0
        67: invokevirtual #367                // Method zombie/scripting/entity/components/crafting/CraftRecipe.needToBeLearn:()Z
        70: ifeq          116
        73: aload_1
        74: aload_0
        75: iconst_1
        76: invokevirtual #370                // Method zombie/characters/IsoGameCharacter.isRecipeKnown:(Lzombie/scripting/entity/components/crafting/CraftRecipe;Z)Z
        79: ifne          116
        82: aload_2
        83: ifnull        99
        86: aload_2
        87: aload_0
        88: invokevirtual #357                // Method zombie/scripting/entity/components/crafting/CraftRecipe.getScriptObjectFullType:()Ljava/lang/String;
        91: invokedynamic #376,  0            // InvokeDynamic #3:makeConcatWithConstants:(Ljava/lang/String;)Ljava/lang/String;
        96: invokevirtual #362                // Method zombie/entity/components/crafting/CraftRecipeMonitor.log:(Ljava/lang/String;)V
        99: getstatic     #345                // Field zombie/debug/DebugType.CraftLogic:Lzombie/debug/DebugType;
       102: aload_0
       103: invokevirtual #357                // Method zombie/scripting/entity/components/crafting/CraftRecipe.getScriptObjectFullType:()Ljava/lang/String;
       106: invokedynamic #376,  0            // InvokeDynamic #3:makeConcatWithConstants:(Ljava/lang/String;)Ljava/lang/String;
       111: invokevirtual #350                // Method zombie/debug/DebugType.debugln:(Ljava/lang/Object;)V
       114: iconst_0
       115: ireturn
       116: iconst_1
       117: ireturn
```

## CraftRecipeManager-javap.txt private static boolean validateHasRequiredSkill(zombie.scripting.entity.components.crafting.CraftRecipe, zombie.characters.IsoGameCharacter, java.util.ArrayList<zombie.inventory.ItemContainer>);

```text
  private static boolean validateHasRequiredSkill(zombie.scripting.entity.components.crafting.CraftRecipe, zombie.characters.IsoGameCharacter, java.util.ArrayList<zombie.inventory.ItemContainer>);
    Code:
         0: aload_0
         1: invokevirtual #377                // Method zombie/scripting/entity/components/crafting/CraftRecipe.getRequiredSkillCount:()I
         4: ifle          64
         7: iconst_0
         8: istore_3
         9: iload_3
        10: aload_0
        11: invokevirtual #377                // Method zombie/scripting/entity/components/crafting/CraftRecipe.getRequiredSkillCount:()I
        14: if_icmpge     64
        17: aload_0
        18: iload_3
        19: invokevirtual #380                // Method zombie/scripting/entity/components/crafting/CraftRecipe.getRequiredSkill:(I)Lzombie/scripting/entity/components/crafting/CraftRecipe$RequiredSkill;
        22: astore        4
        24: aload_1
        25: aload         4
        27: invokevirtual #384                // Method zombie/scripting/entity/components/crafting/CraftRecipe$RequiredSkill.getPerk:()Lzombie/characters/skills/PerkFactory$Perk;
        30: invokevirtual #390                // Method zombie/characters/IsoGameCharacter.getPerkLevel:(Lzombie/characters/skills/PerkFactory$Perk;)I
        33: aload         4
        35: invokevirtual #394                // Method zombie/scripting/entity/components/crafting/CraftRecipe$RequiredSkill.getLevel:()I
        38: if_icmpge     58
        41: aload_2
        42: ifnull        56
        45: aload_0
        46: aload_1
        47: aload_2
        48: invokevirtual #397                // Method zombie/scripting/entity/components/crafting/CraftRecipe.validateBenefitFromRecipeAtHand:(Lzombie/characters/IsoGameCharacter;Ljava/util/ArrayList;)Z
        51: ifne          58
        54: iconst_0
        55: ireturn
        56: iconst_0
        57: ireturn
        58: iinc          3, 1
        61: goto          9
        64: iconst_1
        65: ireturn
```

## CraftRecipeData-javap.txt public boolean perform(zombie.characters.IsoGameCharacter, java.util.List<zombie.entity.components.resources.Resource>, java.util.List<zombie.inventory.InventoryItem>, java.util.ArrayList<zombie.inventory.ItemContainer>);

```text
  public boolean perform(zombie.characters.IsoGameCharacter, java.util.List<zombie.entity.components.resources.Resource>, java.util.List<zombie.inventory.InventoryItem>, java.util.ArrayList<zombie.inventory.ItemContainer>);
    Code:
         0: aload_0
         1: getfield      #122                // Field recipe:Lzombie/scripting/entity/components/crafting/CraftRecipe;
         4: aload_1
         5: aload_0
         6: getfield      #110                // Field craftRecipeMonitor:Lzombie/entity/components/crafting/CraftRecipeMonitor;
         9: aload         4
        11: invokestatic  #403                // Method zombie/entity/components/crafting/recipe/CraftRecipeManager.isValidRecipeForCharacter:(Lzombie/scripting/entity/components/crafting/CraftRecipe;Lzombie/characters/IsoGameCharacter;Lzombie/entity/components/crafting/CraftRecipeMonitor;Ljava/util/ArrayList;)Z
        14: ifne          19
        17: iconst_0
        18: ireturn
        19: aload_0
        20: aload_1
        21: iconst_0
        22: aload_2
        23: aload_3
        24: invokevirtual #417                // Method consumeInputsInternal:(Lzombie/characters/IsoGameCharacter;ZLjava/util/List;Ljava/util/List;)Z
        27: istore        5
        29: iload         5
        31: ifeq          83
        34: aload_0
        35: aload_1
        36: invokevirtual #361                // Method luaCallOnStart:(Lzombie/characters/IsoGameCharacter;)V
        39: aload_0
        40: iconst_0
        41: aconst_null
        42: aload_1
        43: invokevirtual #413                // Method createOutputsInternal:(ZLjava/util/List;Lzombie/characters/IsoGameCharacter;)Z
        46: ifeq          83
        49: aload_0
        50: getfield      #122                // Field recipe:Lzombie/scripting/entity/components/crafting/CraftRecipe;
        53: getfield      #420                // Field zombie/scripting/entity/components/crafting/CraftRecipe.xpAward:Ljava/util/ArrayList;
        56: ifnull        64
        59: aload_0
        60: aload_1
        61: invokevirtual #423                // Method addXP:(Lzombie/characters/IsoGameCharacter;)V
        64: aload_1
        65: checkcast     #426                // class zombie/characters/IsoPlayer
        68: invokevirtual #428                // Method zombie/characters/IsoPlayer.getPlayerCraftHistory:()Lzombie/characters/PlayerCraftHistory;
        71: aload_0
        72: getfield      #122                // Field recipe:Lzombie/scripting/entity/components/crafting/CraftRecipe;
        75: invokevirtual #432                // Method zombie/scripting/entity/components/crafting/CraftRecipe.getName:()Ljava/lang/String;
        78: invokevirtual #435                // Method zombie/characters/PlayerCraftHistory.addCraftHistoryCraftedEvent:(Ljava/lang/String;)V
        81: iconst_1
        82: ireturn
        83: iconst_0
        84: ireturn
```

## HandcraftLogic-javap.txt public boolean performCurrentRecipe();

```text
  public boolean performCurrentRecipe();
    Code:
         0: aload_0
         1: aload_0
         2: getfield      #164                // Field containers:Ljava/util/ArrayList;
         5: invokevirtual #167                // Method isContainersAccessible:(Ljava/util/List;)Z
         8: ifne          13
        11: iconst_0
        12: ireturn
        13: aload_0
        14: aload_0
        15: getfield      #164                // Field containers:Ljava/util/ArrayList;
        18: invokevirtual #171                // Method updateFloorContainer:(Ljava/util/ArrayList;)Z
        21: pop
        22: aload_0
        23: getfield      #75                 // Field recipeData:Lzombie/entity/components/crafting/recipe/CraftRecipeData;
        26: aload_0
        27: getfield      #71                 // Field player:Lzombie/characters/IsoGameCharacter;
        30: aload_0
        31: getfield      #33                 // Field sourceResources:Ljava/util/ArrayList;
        34: aload_0
        35: invokevirtual #175                // Method isManualSelectInputs:()Z
        38: ifeq          45
        41: aconst_null
        42: goto          49
        45: aload_0
        46: getfield      #83                 // Field allItems:Ljava/util/ArrayList;
        49: aload_0
        50: getfield      #164                // Field containers:Ljava/util/ArrayList;
        53: invokevirtual #178                // Method zombie/entity/components/crafting/recipe/CraftRecipeData.perform:(Lzombie/characters/IsoGameCharacter;Ljava/util/List;Ljava/util/List;Ljava/util/ArrayList;)Z
        56: ireturn
```

## HandcraftLogic-javap.txt public boolean isCharacterInRangeOfWorkbench();

```text
  public boolean isCharacterInRangeOfWorkbench();
    Code:
         0: aload_0
         1: getfield      #25                 // Field isoObject:Lzombie/iso/IsoObject;
         4: ifnull        32
         7: aload_0
         8: getfield      #25                 // Field isoObject:Lzombie/iso/IsoObject;
        11: invokevirtual #291                // Method zombie/iso/IsoObject.getSquare:()Lzombie/iso/IsoGridSquare;
        14: aload_0
        15: getfield      #71                 // Field player:Lzombie/characters/IsoGameCharacter;
        18: invokevirtual #297                // Method zombie/iso/IsoGridSquare.DistToProper:(Lzombie/iso/IsoMovingObject;)F
        21: ldc_w         #303                // float 3.0f
        24: fcmpg
        25: ifge          32
        28: iconst_1
        29: goto          33
        32: iconst_0
        33: ireturn
```

## GameEntity-javap.txt public boolean isUsingPlayer(zombie.characters.IsoPlayer);

```text
  public boolean isUsingPlayer(zombie.characters.IsoPlayer);
    Code:
         0: aload_0
         1: invokevirtual #476                // Method getUsingPlayer:()Lzombie/characters/IsoPlayer;
         4: ifnonnull     9
         7: iconst_0
         8: ireturn
         9: aload_1
        10: ifnonnull     15
        13: iconst_0
        14: ireturn
        15: aload_0
        16: invokevirtual #476                // Method getUsingPlayer:()Lzombie/characters/IsoPlayer;
        19: aload_1
        20: if_acmpne     27
        23: iconst_1
        24: goto          28
        27: iconst_0
        28: ireturn
```

## GameEntity-javap.txt public void setUsingPlayer(zombie.characters.IsoPlayer);

```text
  public void setUsingPlayer(zombie.characters.IsoPlayer);
    Code:
         0: aload_0
         1: getfield      #353                // Field usingPlayer:Lzombie/characters/IsoPlayer;
         4: aload_1
         5: if_acmpeq     39
         8: aload_0
         9: aload_1
        10: putfield      #353                // Field usingPlayer:Lzombie/characters/IsoPlayer;
        13: getstatic     #480                // Field zombie/network/GameClient.client:Z
        16: ifne          25
        19: getstatic     #485                // Field zombie/network/GameServer.server:Z
        22: ifeq          39
        25: aload_0
        26: invokevirtual #365                // Method getGameEntityType:()Lzombie/entity/GameEntityType;
        29: getstatic     #490                // Field zombie/entity/GameEntityType.IsoObject:Lzombie/entity/GameEntityType;
        32: if_acmpne     39
        35: aload_0
        36: invokevirtual #493                // Method sendUpdateUsingPlayer:()V
        39: return
```

## IsoGameCharacter-crafting-javap.txt public boolean isRecipeKnown(zombie.scripting.entity.components.crafting.CraftRecipe);

```text
  public boolean isRecipeKnown(zombie.scripting.entity.components.crafting.CraftRecipe);
    Code:
         0: aload_0
         1: aload_1
         2: iconst_0
         3: invokevirtual #9568               // Method isRecipeKnown:(Lzombie/scripting/entity/components/crafting/CraftRecipe;Z)Z
         6: ireturn
```

## IsoGameCharacter-crafting-javap.txt public boolean isRecipeKnown(zombie.scripting.entity.components.crafting.CraftRecipe, boolean);

```text
  public boolean isRecipeKnown(zombie.scripting.entity.components.crafting.CraftRecipe, boolean);
    Code:
         0: iload_2
         1: ifne          16
         4: getstatic     #2811               // Field zombie/SandboxOptions.instance:Lzombie/SandboxOptions;
         7: getfield      #9560               // Field zombie/SandboxOptions.seeNotLearntRecipe:Lzombie/SandboxOptions$BooleanSandboxOption;
        10: invokevirtual #3144               // Method zombie/SandboxOptions$BooleanSandboxOption.getValue:()Z
        13: ifne          23
        16: aload_0
        17: invokevirtual #4788               // Method isKnowAllRecipes:()Z
        20: ifeq          25
        23: iconst_1
        24: ireturn
        25: aload_1
        26: invokevirtual #9572               // Method zombie/scripting/entity/components/crafting/CraftRecipe.needToBeLearn:()Z
        29: ifeq          80
        32: aload_0
        33: invokevirtual #4353               // Method getKnownRecipes:()Ljava/util/List;
        36: aload_1
        37: invokevirtual #9577               // Method zombie/scripting/entity/components/crafting/CraftRecipe.getName:()Ljava/lang/String;
        40: invokeinterface #4356,  2         // InterfaceMethod java/util/List.contains:(Ljava/lang/Object;)Z
        45: ifne          80
        48: aload_0
        49: invokevirtual #4353               // Method getKnownRecipes:()Ljava/util/List;
        52: aload_1
        53: invokevirtual #9578               // Method zombie/scripting/entity/components/crafting/CraftRecipe.getMetaRecipe:()Ljava/lang/String;
        56: invokeinterface #4356,  2         // InterfaceMethod java/util/List.contains:(Ljava/lang/Object;)Z
        61: ifne          80
        64: aload_0
        65: invokevirtual #4353               // Method getKnownRecipes:()Ljava/util/List;
        68: aload_1
        69: invokevirtual #9581               // Method zombie/scripting/entity/components/crafting/CraftRecipe.getTranslationName:()Ljava/lang/String;
        72: invokeinterface #4356,  2         // InterfaceMethod java/util/List.contains:(Ljava/lang/Object;)Z
        77: ifeq          84
        80: iconst_1
        81: goto          85
        84: iconst_0
        85: ireturn
```

## IsoGameCharacter-crafting-javap.txt public boolean learnRecipe(java.lang.String);

```text
  public boolean learnRecipe(java.lang.String);
    Code:
         0: aload_0
         1: aload_1
         2: iconst_1
         3: invokevirtual #9594               // Method learnRecipe:(Ljava/lang/String;Z)Z
         6: ireturn
```

## IsoGameCharacter-crafting-javap.txt public boolean learnRecipe(java.lang.String, boolean);

```text
  public boolean learnRecipe(java.lang.String, boolean);
    Code:
         0: aload_0
         1: aload_1
         2: iconst_1
         3: invokevirtual #9584               // Method isRecipeKnown:(Ljava/lang/String;Z)Z
         6: ifne          34
         9: aload_0
        10: invokevirtual #4353               // Method getKnownRecipes:()Ljava/util/List;
        13: aload_1
        14: invokeinterface #4622,  2         // InterfaceMethod java/util/List.add:(Ljava/lang/Object;)Z
        19: pop
        20: iload_2
        21: ifeq          32
        24: getstatic     #5144               // Field zombie/scripting/ScriptManager.instance:Lzombie/scripting/ScriptManager;
        27: aload_0
        28: aload_1
        29: invokevirtual #9596               // Method zombie/scripting/ScriptManager.checkMetaRecipe:(Lzombie/characters/IsoGameCharacter;Ljava/lang/String;)V
        32: iconst_1
        33: ireturn
        34: iconst_0
        35: ireturn
```

## PZOPT_EFFECTIVE 知识接口复核

pzopt优先类路径下的IsoGameCharacter知识方法与本机原版JAR方法，忽略常量池编号后不一致。下列片段来自有效覆盖类。

逐分支复核的静态推断：差异来自返回分支重排，所审知识判定逻辑一致。`isRecipeKnown(CraftRecipe, boolean)`依次允许非严格模式下的沙盒显示选项、KnowAll、不要求学习，或knownRecipes包含name/metaRecipe/translationName；严格模式跳过沙盒显示选项。`learnRecipe(String, boolean)`仍先判已知、加入知识表、按参数检查metaRecipe。本结论不等于整类等价或实机兼容通过；本轮没有记录运行时类加载来源。

```text
  public boolean isRecipeKnown(zombie.scripting.entity.components.crafting.CraftRecipe, boolean);
    Code:
         0: iload_2
         1: ifne          16
         4: getstatic     #2878               // Field zombie/SandboxOptions.instance:Lzombie/SandboxOptions;
         7: getfield      #9817               // Field zombie/SandboxOptions.seeNotLearntRecipe:Lzombie/SandboxOptions$BooleanSandboxOption;
        10: invokevirtual #3211               // Method zombie/SandboxOptions$BooleanSandboxOption.getValue:()Z
        13: ifne          86
        16: aload_0
        17: invokevirtual #4877               // Method isKnowAllRecipes:()Z
        20: ifne          86
        23: aload_1
        24: invokevirtual #9829               // Method zombie/scripting/entity/components/crafting/CraftRecipe.needToBeLearn:()Z
        27: ifeq          78
        30: aload_0
        31: invokevirtual #4442               // Method getKnownRecipes:()Ljava/util/List;
        34: aload_1
        35: invokevirtual #9834               // Method zombie/scripting/entity/components/crafting/CraftRecipe.getName:()Ljava/lang/String;
        38: invokeinterface #4445,  2         // InterfaceMethod java/util/List.contains:(Ljava/lang/Object;)Z
        43: ifne          78
        46: aload_0
        47: invokevirtual #4442               // Method getKnownRecipes:()Ljava/util/List;
        50: aload_1
        51: invokevirtual #9835               // Method zombie/scripting/entity/components/crafting/CraftRecipe.getMetaRecipe:()Ljava/lang/String;
        54: invokeinterface #4445,  2         // InterfaceMethod java/util/List.contains:(Ljava/lang/Object;)Z
        59: ifne          78
        62: aload_0
        63: invokevirtual #4442               // Method getKnownRecipes:()Ljava/util/List;
        66: aload_1
        67: invokevirtual #9838               // Method zombie/scripting/entity/components/crafting/CraftRecipe.getTranslationName:()Ljava/lang/String;
        70: invokeinterface #4445,  2         // InterfaceMethod java/util/List.contains:(Ljava/lang/Object;)Z
        75: ifeq          82
        78: iconst_1
        79: goto          87
        82: iconst_0
        83: goto          87
        86: iconst_1
        87: ireturn
```

```text
  public boolean learnRecipe(java.lang.String, boolean);
    Code:
         0: aload_0
         1: aload_1
         2: iconst_1
         3: invokevirtual #9841               // Method isRecipeKnown:(Ljava/lang/String;Z)Z
         6: ifne          34
         9: aload_0
        10: invokevirtual #4442               // Method getKnownRecipes:()Ljava/util/List;
        13: aload_1
        14: invokeinterface #4711,  2         // InterfaceMethod java/util/List.add:(Ljava/lang/Object;)Z
        19: pop
        20: iload_2
        21: ifeq          32
        24: getstatic     #5231               // Field zombie/scripting/ScriptManager.instance:Lzombie/scripting/ScriptManager;
        27: aload_0
        28: aload_1
        29: invokevirtual #9853               // Method zombie/scripting/ScriptManager.checkMetaRecipe:(Lzombie/characters/IsoGameCharacter;Ljava/lang/String;)V
        32: iconst_1
        33: ireturn
        34: iconst_0
        35: ireturn
```

## BaseCraftingLogic-javap.txt public boolean isContainersAccessible(java.util.List<zombie.inventory.ItemContainer>);

```text
  public boolean isContainersAccessible(java.util.List<zombie.inventory.ItemContainer>);
    Code:
         0: iconst_0
         1: istore_2
         2: iload_2
         3: aload_1
         4: invokeinterface #357,  1          // InterfaceMethod java/util/List.size:()I
         9: if_icmpge     190
        12: aload_1
        13: iload_2
        14: invokeinterface #358,  2          // InterfaceMethod java/util/List.get:(I)Ljava/lang/Object;
        19: checkcast     #726                // class zombie/inventory/ItemContainer
        22: astore_3
        23: aload_3
        24: invokevirtual #728                // Method zombie/inventory/ItemContainer.getOutermostContainer:()Lzombie/inventory/ItemContainer;
        27: astore        4
        29: aload         4
        31: invokevirtual #732                // Method zombie/inventory/ItemContainer.getVehiclePart:()Lzombie/vehicles/VehiclePart;
        34: ifnull        85
        37: aload         4
        39: invokevirtual #732                // Method zombie/inventory/ItemContainer.getVehiclePart:()Lzombie/vehicles/VehiclePart;
        42: invokevirtual #736                // Method zombie/vehicles/VehiclePart.getVehicle:()Lzombie/vehicles/BaseVehicle;
        45: ifnull        85
        48: aload         4
        50: invokevirtual #732                // Method zombie/inventory/ItemContainer.getVehiclePart:()Lzombie/vehicles/VehiclePart;
        53: invokevirtual #736                // Method zombie/vehicles/VehiclePart.getVehicle:()Lzombie/vehicles/BaseVehicle;
        56: aload         4
        58: invokevirtual #732                // Method zombie/inventory/ItemContainer.getVehiclePart:()Lzombie/vehicles/VehiclePart;
        61: invokevirtual #742                // Method zombie/vehicles/VehiclePart.getIndex:()I
        64: aload_0
        65: getfield      #78                 // Field player:Lzombie/characters/IsoGameCharacter;
        68: invokevirtual #745                // Method zombie/vehicles/BaseVehicle.canAccessContainer:(ILzombie/characters/IsoGameCharacter;)Z
        71: ifne          85
        74: getstatic     #751                // Field zombie/debug/DebugType.CraftLogic:Lzombie/debug/DebugType;
        77: ldc_w         #754                // String Can\'t craft: can\'t access vehicle container
        80: invokevirtual #756                // Method zombie/debug/DebugType.debugln:(Ljava/lang/Object;)V
        83: iconst_0
        84: ireturn
        85: aload         4
        87: invokevirtual #732                // Method zombie/inventory/ItemContainer.getVehiclePart:()Lzombie/vehicles/VehiclePart;
        90: ifnonnull     131
        93: aload         4
        95: invokevirtual #759                // Method zombie/inventory/ItemContainer.getSquare:()Lzombie/iso/IsoGridSquare;
        98: ifnull        131
       101: aload         4
       103: invokevirtual #759                // Method zombie/inventory/ItemContainer.getSquare:()Lzombie/iso/IsoGridSquare;
       106: aload_0
       107: getfield      #78                 // Field player:Lzombie/characters/IsoGameCharacter;
       110: invokevirtual #763                // Method zombie/iso/IsoGridSquare.DistToProper:(Lzombie/iso/IsoMovingObject;)F
       113: ldc_w         #769                // float 2.5f
       116: fcmpl
       117: ifle          131
       120: getstatic     #751                // Field zombie/debug/DebugType.CraftLogic:Lzombie/debug/DebugType;
       123: ldc_w         #770                // String Can\'t craft: container too far
       126: invokevirtual #756                // Method zombie/debug/DebugType.debugln:(Ljava/lang/Object;)V
       129: iconst_0
       130: ireturn
       131: aload         4
       133: invokevirtual #772                // Method zombie/inventory/ItemContainer.getParent:()Lzombie/iso/IsoObject;
       136: ifnull        184
       139: aload         4
       141: invokevirtual #772                // Method zombie/inventory/ItemContainer.getParent:()Lzombie/iso/IsoObject;
       144: astore        6
       146: aload         6
       148: instanceof    #776                // class zombie/iso/objects/IsoThumpable
       151: ifeq          184
       154: aload         6
       156: checkcast     #776                // class zombie/iso/objects/IsoThumpable
       159: astore        5
       161: aload         5
       163: aload_0
       164: getfield      #78                 // Field player:Lzombie/characters/IsoGameCharacter;
       167: invokevirtual #778                // Method zombie/iso/objects/IsoThumpable.isLockedToCharacter:(Lzombie/characters/IsoGameCharacter;)Z
       170: ifeq          184
       173: getstatic     #751                // Field zombie/debug/DebugType.CraftLogic:Lzombie/debug/DebugType;
       176: ldc_w         #782                // String Can\'t craft: thumpable container is locked to the character
       179: invokevirtual #756                // Method zombie/debug/DebugType.debugln:(Ljava/lang/Object;)V
       182: iconst_0
       183: ireturn
       184: iinc          2, 1
       187: goto          2
       190: iconst_1
       191: ireturn
```

## BaseCraftingLogic-javap.txt public boolean canPerformCurrentRecipe();

```text
  public boolean canPerformCurrentRecipe();
    Code:
         0: aload_0
         1: iconst_0
         2: putfield      #71                 // Field cachedCanPerformDirty:Z
         5: aload_0
         6: aload_0
         7: getfield      #115                // Field recipeData:Lzombie/entity/components/crafting/recipe/CraftRecipeData;
        10: aload_0
        11: getfield      #78                 // Field player:Lzombie/characters/IsoGameCharacter;
        14: aload_0
        15: getfield      #26                 // Field sourceResources:Ljava/util/ArrayList;
        18: aload_0
        19: invokevirtual #911                // Method isManualSelectInputs:()Z
        22: ifeq          29
        25: aconst_null
        26: goto          33
        29: aload_0
        30: getfield      #19                 // Field allItems:Ljava/util/ArrayList;
        33: iconst_1
        34: aload_0
        35: getfield      #23                 // Field containers:Ljava/util/ArrayList;
        38: invokevirtual #847                // Method zombie/entity/components/crafting/recipe/CraftRecipeData.canPerform:(Lzombie/characters/IsoGameCharacter;Ljava/util/List;Ljava/util/List;ZLjava/util/ArrayList;)Z
        41: putfield      #908                // Field cachedCanPerform:Z
        44: aload_0
        45: getfield      #115                // Field recipeData:Lzombie/entity/components/crafting/recipe/CraftRecipeData;
        48: invokevirtual #571                // Method zombie/entity/components/crafting/recipe/CraftRecipeData.getRecipe:()Lzombie/scripting/entity/components/crafting/CraftRecipe;
        51: ifnull        79
        54: aload_0
        55: getfield      #115                // Field recipeData:Lzombie/entity/components/crafting/recipe/CraftRecipeData;
        58: invokevirtual #571                // Method zombie/entity/components/crafting/recipe/CraftRecipeData.getRecipe:()Lzombie/scripting/entity/components/crafting/CraftRecipe;
        61: invokevirtual #914                // Method zombie/scripting/entity/components/crafting/CraftRecipe.isAnySurfaceCraft:()Z
        64: ifeq          79
        67: aload_0
        68: invokevirtual #871                // Method isCharacterInRangeOfWorkbench:()Z
        71: ifne          79
        74: aload_0
        75: iconst_0
        76: putfield      #908                // Field cachedCanPerform:Z
        79: aload_0
        80: getfield      #115                // Field recipeData:Lzombie/entity/components/crafting/recipe/CraftRecipeData;
        83: invokevirtual #571                // Method zombie/entity/components/crafting/recipe/CraftRecipeData.getRecipe:()Lzombie/scripting/entity/components/crafting/CraftRecipe;
        86: ifnull        114
        89: aload_0
        90: getfield      #115                // Field recipeData:Lzombie/entity/components/crafting/recipe/CraftRecipeData;
        93: invokevirtual #571                // Method zombie/entity/components/crafting/recipe/CraftRecipeData.getRecipe:()Lzombie/scripting/entity/components/crafting/CraftRecipe;
        96: invokevirtual #868                // Method zombie/scripting/entity/components/crafting/CraftRecipe.requiresSpecificWorkstation:()Z
        99: ifeq          114
       102: aload_0
       103: invokevirtual #917                // Method hasRequiredWorkstation:()Z
       106: ifne          114
       109: aload_0
       110: iconst_0
       111: putfield      #908                // Field cachedCanPerform:Z
       114: aload_0
       115: getfield      #908                // Field cachedCanPerform:Z
       118: ireturn
```

## CraftRecipeData-javap.txt public boolean setManualInputsFor(zombie.scripting.entity.components.crafting.InputScript, java.util.ArrayList<zombie.inventory.InventoryItem>);

```text
  public boolean setManualInputsFor(zombie.scripting.entity.components.crafting.InputScript, java.util.ArrayList<zombie.inventory.InventoryItem>);
    Code:
         0: aload_0
         1: invokevirtual #873                // Method getRecipe:()Lzombie/scripting/entity/components/crafting/CraftRecipe;
         4: ifnull        18
         7: aload_0
         8: invokevirtual #873                // Method getRecipe:()Lzombie/scripting/entity/components/crafting/CraftRecipe;
        11: aload_1
        12: invokevirtual #228                // Method zombie/scripting/entity/components/crafting/CraftRecipe.containsIO:(Lzombie/scripting/entity/components/crafting/CraftRecipe$IOScript;)Z
        15: ifne          20
        18: iconst_0
        19: ireturn
        20: aload_0
        21: aload_1
        22: invokevirtual #232                // Method getDataForInputScript:(Lzombie/scripting/entity/components/crafting/InputScript;)Lzombie/entity/components/crafting/recipe/CraftRecipeData$InputScriptData;
        25: astore_3
        26: aload_1
        27: invokevirtual #270                // Method zombie/scripting/entity/components/crafting/InputScript.getResourceType:()Lzombie/entity/components/resources/ResourceType;
        30: getstatic     #274                // Field zombie/entity/components/resources/ResourceType.Item:Lzombie/entity/components/resources/ResourceType;
        33: if_acmpne     164
        36: aload_3
        37: invokevirtual #307                // Method zombie/entity/components/crafting/recipe/CraftRecipeData$InputScriptData.getLastInputItem:()Lzombie/inventory/InventoryItem;
        40: ifnull        55
        43: aload_3
        44: aload_3
        45: invokevirtual #307                // Method zombie/entity/components/crafting/recipe/CraftRecipeData$InputScriptData.getLastInputItem:()Lzombie/inventory/InventoryItem;
        48: invokevirtual #310                // Method zombie/entity/components/crafting/recipe/CraftRecipeData$InputScriptData.removeInputItem:(Lzombie/inventory/InventoryItem;)Z
        51: pop
        52: goto          36
        55: iconst_0
        56: istore        4
        58: iload         4
        60: aload_2
        61: invokevirtual #126                // Method java/util/ArrayList.size:()I
        64: if_icmpge     159
        67: aload_2
        68: iload         4
        70: invokevirtual #130                // Method java/util/ArrayList.get:(I)Ljava/lang/Object;
        73: checkcast     #297                // class zombie/inventory/InventoryItem
        76: astore        5
        78: aload         5
        80: invokevirtual #1604               // Method zombie/inventory/InventoryItem.getContainer:()Lzombie/inventory/ItemContainer;
        83: ifnonnull     109
        86: aload         5
        88: invokevirtual #1608               // Method zombie/inventory/InventoryItem.getWorldItem:()Lzombie/iso/objects/IsoWorldInventoryObject;
        91: ifnull        153
        94: aload         5
        96: invokevirtual #1608               // Method zombie/inventory/InventoryItem.getWorldItem:()Lzombie/iso/objects/IsoWorldInventoryObject;
        99: invokevirtual #1612               // Method zombie/iso/objects/IsoWorldInventoryObject.getWorldObjectIndex:()I
       102: iconst_m1
       103: if_icmpne     109
       106: goto          153
       109: aload_0
       110: aload         5
       112: invokevirtual #290                // Method containsInputItem:(Lzombie/inventory/InventoryItem;)Z
       115: ifeq          121
       118: goto          153
       121: aload_3
       122: aload         5
       124: invokevirtual #319                // Method zombie/entity/components/crafting/recipe/CraftRecipeData$InputScriptData.addInputItem:(Lzombie/inventory/InventoryItem;)Z
       127: ifeq          153
       130: getstatic     #253                // Field zombie/debug/DebugType.CraftLogic:Lzombie/debug/DebugType;
       133: aload_2
       134: iload         4
       136: invokevirtual #130                // Method java/util/ArrayList.get:(I)Ljava/lang/Object;
       139: checkcast     #297                // class zombie/inventory/InventoryItem
       142: invokevirtual #296                // Method zombie/inventory/InventoryItem.getFullType:()Ljava/lang/String;
       145: invokedynamic #1617,  0           // InvokeDynamic #24:makeConcatWithConstants:(Ljava/lang/String;)Ljava/lang/String;
       150: invokevirtual #465                // Method zombie/debug/DebugType.println:(Ljava/lang/String;)V
       153: iinc          4, 1
       156: goto          58
       159: aload_3
       160: invokevirtual #313                // Method zombie/entity/components/crafting/recipe/CraftRecipeData$InputScriptData.isInputItemsSatisfied:()Z
       163: ireturn
       164: iconst_0
       165: ireturn
```
