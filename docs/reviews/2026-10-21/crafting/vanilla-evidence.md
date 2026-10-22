# 当前安装原版制作证据

> 2026-10-21｜状态：只读取证完成；未实机验证｜[核查结论](../commissioned-crafting-review.md)

原始文件只读，截取时保留当前原版行号；每个完整文件的哈希在[基线](baseline.json)。

## E1 木叉配方

`media/scripts/generated/recipes/recipes_carving.txt`，行337～357；SHA256见baseline.json。

```text
337|     craftRecipe CarveWoodenFork
338|     {
339|         time = 200,
340|         Tags = AnySurfaceCraft,
341|         xpAward = Carving:20,
342|         SkillRequired = Carving:2,
343|         timedAction = SharpenStakeWood,
344|         category = Carving,
345|         NeedToBeLearn = true,
346|         AutoLearnAny = Carving:4,
347|         inputs
348|         {
349|             item 1 tags[base:sharpknife] mode:keep flags[Prop1;IsNotDull;MayDegradeLight],
350|             item 1 [Base.SmallHandle;Base.WoodenSpoon] flags[Prop2],
351|         }
352|         outputs
353|         {
354|             item 1 Base.WoodenFork,
355|         }
356|     }
357| 
```

## E2 工作台

`media/scripts/generated/entities/outdoors/entity_chopping_block.txt`，行1～40；SHA256见baseline.json。

```text
1| module Base
2| {
3|     entity Chopping_Block
4|     {
5|         component UiConfig
6|         {
7|             xuiSkin = default,
8|             entityStyle = ES_Chopping_Block,
9|             uiEnabled = true,
10|         }
11|         component CraftBench
12|         {
13|             Recipes = AnySurfaceCraft;ChoppingBlock,
14|         }
15|         component SpriteConfig
16|         {
17|             face SINGLE
18|             {
19|                 layer
20|                 {
21|                     row = crafted_02_85,
22|                 }
23|             }
24|         }
25|         component CraftRecipe
26|         {
27|             timedAction = BuildLowNoTool,
28|             time = 50,
29|             SkillRequired = Woodwork:1,
30|             xpAward = Woodwork:10,
31|             category = Outdoors,
32|             Tooltip = Tooltip_craft_choppingBlockDesc,
33|             inputs
34|             {
35|                 item 1 [Base.Log],
36|                 item 1 tags[base:crudesaw;base:saw] mode:keep flags[MayDegradeLight],
37|             }
38|         }
39|     }
40| }
```

## E3 取消回调

`media/lua/shared/Entity/TimedActions/ISHandcraftAction.lua`，行154～172；SHA256见baseline.json。

```text
154| function ISHandcraftAction:stop()
155| 	--log(DebugType.CraftLogic, "ISHandcraftAction.stop")
156| 
157| 	self:clearItemsProgressBar(false);
158|     ISBaseTimedAction.stop(self);
159| 	
160| 	if self.sound and self.character:getEmitter():isPlaying(self.sound) then
161| 		self.character:stopOrTriggerSound(self.sound);
162| 	end
163| 	
164| 	if self.onCancelFunc then
165| 		self.onCancelFunc(self.onCancelTarget);
166| 	end
167| 
168| 	if self.onCompleteFunc then
169| 		self.onCompleteFunc(self.onCompleteTarget);
170| 	end
171| end
172| 
```

## E4 单人执行与提交

`media/lua/shared/Entity/TimedActions/ISHandcraftAction.lua`，行173～202；SHA256见baseline.json。

```text
173| function ISHandcraftAction:perform()
174| 	--log(DebugType.CraftLogic, "ISHandcraftAction.perform")
175| 
176|     if not isClient() and self.eatPercentage > 0 and self.logic:getRecipeData() then
177|         self.logic:getRecipeData():setEatPercentage(self.eatPercentage)
178|     end
179| 
180| 	self:clearItemsProgressBar(false);
181| 	
182| 	if self.sound and self.character:getEmitter():isPlaying(self.sound) then
183| 		self.character:stopOrTriggerSound(self.sound);
184| 	end
185|     if self.actionScript and self.actionScript:getCompletionSound() ~= nil then
186|         self.character:playSound(self.actionScript:getCompletionSound());
187|     end
188| 
189| 	ISInventoryPage.dirtyUI();
190| 
191| 	if not isClient() then
192| 		self:performRecipe();
193| 	end
194| 	
195| 	-- spurcival: super.perform() must happen AFTER performRecipe() as super.perform() kicks off the next multicraft.
196| 	ISBaseTimedAction.perform(self);
197| 
198| 	if isClient() and self.onCompleteFunc then
199| 		self.onCompleteFunc(self.onCompleteTarget);
200| 	end
201| end
202| 
```

## E5 原版制作效果

`media/lua/shared/Entity/TimedActions/ISHandcraftAction.lua`，行221～252；SHA256见baseline.json。

```text
221| function ISHandcraftAction:performRecipe()
222| 	if self.logic then
223| 		if self.logic:performCurrentRecipe() then
224| 			-- perform succeeded
225| 			local items = ArrayList.new();
226| 			self.logic:getCreatedOutputItems(items);
227| 
228| 			for i=0,items:size()-1 do
229| 				local item = items:get(i);
230| 				Actions.addOrDropItem(self.character, item)
231| 			end
232| 
233|             self.logic:getRecipeData():luaCallOnCreate(self.character);
234|             self.logic:getRecipeData():processDestroyAndUsedItems(self.character); -- todo handle syncing items and inventory stuff here
235| 
236| 			if items:size() == 1 then
237| 				local resItem = items:get(0)
238| 				local modData = resItem:getModData()
239| 				local usedItems = self.logic:getRecipeData():getAllConsumedItems()
240| 				for i=0, usedItems:size()-1 do
241| 					local item = usedItems:get(i)
242| 					if modData[item:getFullType()] == nil then
243| 						modData[item:getFullType()] = 0
244| 					end
245| 					modData[item:getFullType()] = modData[item:getFullType()] + 1
246| 				end
247| 			end
248| 		end
249| 	end
250| end
251| 
252| --ADDED A MULTIPLIER TO THE BASE TIME VALUE
```

## E6 实例构造

`media/lua/shared/Entity/TimedActions/ISHandcraftAction.lua`，行391～419；SHA256见baseline.json。

```text
391| function ISHandcraftAction:new(character, craftRecipe, containers, isoObject, craftBench, manualInputs, items, recipeItem, variableInputRatio, eatPercentage)
392| 	log(DebugType.CraftLogic, "Creating handcraft action")
393| 	local o = ISBaseTimedAction.new(self, character);
394| 
395| 	o.stopOnAim = false;
396| 	o.character = character;
397| 	o.isoObject = isoObject;
398| 	o.craftBench = craftBench; -- may be nil, if not nil the craftbench is a component of the supplied isoObject.
399|     o.containers = containers;
400| 	o.manualInputs = convertToPZNetTable(manualInputs); -- a non-ordered key,value table where key=integer index of InputScript, and value=ArrayList of InventoryItem's.
401| 	o.craftRecipe = craftRecipe;
402| 	o.actionScript = o.craftRecipe and o.craftRecipe:getTimedActionScript();
403| 	--o.usesCustomDelta = true;
404| -- 	log(DebugType.CraftLogic, tostring(craftRecipe:getName()) .. " - can walk " .. tostring(craftRecipe:isCanWalk()))
405| 	o.stopOnWalk = not craftRecipe:isCanWalk();
406| 	if character and (character:hasTrait(CharacterTrait.ALL_THUMBS) or character:isWearingAwkwardGloves()) then
407| 	    o.stopOnWalk = true;
408|     end
409| -- 	o.stopOnWalk = true;
410| 	o.stopOnRun = true;
411| 	o.maxTime = o:getDuration();
412| 
413| 	o.items = items;
414| 	o.recipeItem = recipeItem;
415| 	o.variableInputRatio = variableInputRatio or 1;
416| 	o.eatPercentage = eatPercentage or 0;
417|     o.craftStarted = false
418| 	return o
419| end
```

## E7 产物入包或落地

`media/lua/shared/ActionManager.lua`，行4～24；SHA256见baseline.json。

```text
4| function Actions.addOrDropItem(character, item)
5| 	local inv = character:getInventory()
6| 	local itemWasAddedToInventory = false
7| 	if not inv:contains(item) then
8| 		inv:AddItem(item)
9| 		itemWasAddedToInventory = true
10| 	end
11| 	if inv:getCapacityWeight() > inv:getEffectiveCapacity(character) then
12| 		if inv:contains(item) then
13| 			inv:Remove(item)
14| 			itemWasAddedToInventory = false
15| 		end
16| 		character:getCurrentSquare():AddWorldInventoryItem(item,
17| 			character:getX() - math.floor(character:getX()),
18| 			character:getY() - math.floor(character:getY()),
19| 			character:getZ() - math.floor(character:getZ()))
20| 	end
21| 	if itemWasAddedToInventory then
22| 	    sendAddItemToContainer(inv, item);
23| 	end
24| end
```

## E8 手动输入与开工校验

`media/lua/shared/Entity/TimedActions/ISHandcraftAction.lua`，行95～129；SHA256见baseline.json。

```text
95| 		end
96| 		self.logic:setManualSelectInputs(true);
97| 		self.logic:clearManualInputs();
98| 		
99| 		--log(DebugType.CraftLogic, "-= reading manual inputs =-")
100| 		for inputIndex, items in pairs(self.manualInputs) do
101| 			local inputScript = self.craftRecipe:getIOForIndex(inputIndex);
102| 			if (not inputScript) or (not self.logic:setManualInputsFor(inputScript, items)) then
103| 				log(DebugType.CraftLogic, "ISHandcraftAction.start -> failed to set manual input items for recipe.")
104| 			end
105| 		end
106| 
107| 		-- This call is required so CraftRecipeData.CachedData.addAppliedData() is called for manualInputs.
108| 		-- Without it, the CraftRecipeData.getAllInputItems() call below won't return manualInputs.
109| 		self.logic:canPerformCurrentRecipe()
110| 
111| 		if not self.force and not self.logic:canPerformCurrentRecipe() then
112| 			log(DebugType.CraftLogic, "ISHandcraftAction.start -> canPerformCurrentRecipe failed.")
113| 			self:forceStop();
114| 			return;
115| 		end
116| 	end
117| 
118| 	if self.items then
119| 		if isClient() then
120| 			self:fixMovedItems(self.items)
121| 		end
122|     else
123| 		-- populate with what recipe has now filled
124| 		if self.logic:getRecipeData() then
125| 			self.items = self.logic:getRecipeData():getAllInputItems()
126| 		end
127| 	end
128| 
129| 	self:clearItemsProgressBar(true);
```

## E9 原版工作台窗口占用

`media/lua/client/Entity/ISUI/ISBaseEntityWindow.lua`，行116～135；SHA256见baseline.json。

```text
116| function ISBaseEntityWindow:close()
117|     if self.hasClosedWindowInstance then --to prevent occasional double calling of close due to a call in self.update.
118|         return;
119|     end
120|     self.hasClosedWindowInstance = true;
121|     ISCollapsableWindow.close(self);
122|     ISEntityUI.OnCloseWindow(self);
123|     if JoypadState.players[self.playerNum+1] then
124|         if self.unfocusRecursive then
125|             self:unfocusRecursive(getFocusForPlayer(self.playerNum), self.playerNum);
126|         elseif isJoypadFocusOnElementOrDescendant(self.playerNum, self) then
127|             setJoypadFocus(self.playerNum, nil);
128|         end
129|     end
130|     if self.entity then
131|         self.entity:setUsingPlayer(nil);
132|     end
133|     self:removeFromUIManager();
134| end
135| 
```

## E10 原版工作台窗口设占用

`media/lua/client/Entity/ISUI/ISBaseEntityWindow.lua`，行199～209；SHA256见baseline.json。

```text
199| 
200|     o.maximumHeightPercent = -1;
201|     o:setWantKeyEvents(true);
202| 
203|     o.overrideBPrompt = true;
204|     if o.entity and o.player then
205|         o.entity:setUsingPlayer(o.player);
206|     end
207| 
208|     return o
209| end
```
