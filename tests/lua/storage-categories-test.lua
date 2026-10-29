package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local Filter=require "EmberRoutesProbe/StorageFilter"
local Sort=require "EmberRoutesProbe/SortPolicy"

local count=0
local function check(val,msg)
    count=count+1
    assert(val,msg)
end

local function fakeItem(data)
    local item={}
    function item:getFullType() return data.fullType or "Base.Unknown" end
    function item:getCategory() return data.category or "Item" end
    function item:getDisplayCategory() return data.display or "" end
    function item:isFood() return data.food==true end
    function item:isRotten() return data.rotten==true end
    function item:isCooked() return data.cooked==true end
    function item:isRanged() return data.ranged==true end
    function item:IsClothing() return data.clothing==true end
    function item:isClothing() return data.clothing==true end
    function item:IsContainer() return data.container==true end
    function item:isContainer() return data.container==true end
    function item:getAge() return data.age or 0 end
    function item:getOffAgeMax() return data.perishable and 10 or 1000000000 end
    return item
end

-- 1. Food Triad + Rotten
local stew = fakeItem({fullType="Base.Stew",food=true,cooked=true,perishable=true})
local apple = fakeItem({fullType="Base.Apple",food=true,perishable=true})
local canned = fakeItem({fullType="Base.CannedBeans",food=true,perishable=false})
local rottenApple = fakeItem({fullType="Base.Apple",food=true,perishable=true,rotten=true})

check(Filter.classify(Filter.describe(stew),stew)=="food.meals","cooked meals classified to food.meals")
check(Filter.classify(Filter.describe(apple),apple)=="food.perishable","fresh food classified to food.perishable")
check(Filter.classify(Filter.describe(canned),canned)=="food.stable","shelf-stable food classified to food.stable")
check(Filter.classify(Filter.describe(rottenApple),rottenApple)=="scrap.compost","rotten food diverted to scrap.compost")

-- 2. Medical Subcategories & Rag handling
local bandage = fakeItem({fullType="Base.Bandage",display="Medical"})
local sterilizedRag = fakeItem({fullType="Base.AlcoholRippedSheets",display="Medical"})
local dirtyRag = fakeItem({fullType="Base.RippedSheetsDirty",display="Scrap"})
local pills = fakeItem({fullType="Base.PillsPainkiller",display="Medical"})
local antibiotics = fakeItem({fullType="Base.Antibiotics",display="Medical"})

check(Filter.classify(Filter.describe(bandage),bandage)=="medical.bandages","bandage classified to medical.bandages")
check(Filter.classify(Filter.describe(sterilizedRag),sterilizedRag)=="medical.bandages","sterilized rag classified to medical.bandages")
check(Filter.classify(Filter.describe(dirtyRag),dirtyRag)=="scrap.waste","dirty rag classified to scrap.waste")
check(Filter.classify(Filter.describe(pills),pills)=="medical.pills","painkillers classified to medical.pills")
check(Filter.classify(Filter.describe(antibiotics),antibiotics)=="medical.pills","antibiotics classified to medical.pills")

-- 3. Apparel vs Trade (Disambiguation)
local vest = fakeItem({fullType="Base.Vest_BulletCivilian",clothing=true,category="Clothing"})
local helmet = fakeItem({fullType="Base.Hat_CrashHelmet",clothing=true,category="Clothing"})
local shirt = fakeItem({fullType="Base.Tshirt_White",clothing=true,category="Clothing"})
local glasses = fakeItem({fullType="Base.Glasses_Reading",clothing=true,category="Clothing"})
local backpack = fakeItem({fullType="Base.Bag_BigHikingBag",container=true,category="Container"})
local goldRing = fakeItem({fullType="Base.Ring_Gold",clothing=false,category="Clothing"})
local diamondNecklace = fakeItem({fullType="Base.Necklace_GoldDiamond",category="Clothing"})
local cash = fakeItem({fullType="Base.Money"})

check(Filter.classify(Filter.describe(vest),vest)=="apparel.armor","armor vest classified to apparel.armor")
check(Filter.classify(Filter.describe(helmet),helmet)=="apparel.armor","helmet classified to apparel.armor")
check(Filter.classify(Filter.describe(shirt),shirt)=="apparel.clothing","clothing classified to apparel.clothing")
check(Filter.classify(Filter.describe(glasses),glasses)=="apparel.clothing","glasses classified to apparel.clothing")
check(Filter.classify(Filter.describe(backpack),backpack)=="apparel.bags","backpack classified to apparel.bags")
check(Filter.classify(Filter.describe(goldRing),goldRing)=="trade.valuables","gold ring classified to trade.valuables")
check(Filter.classify(Filter.describe(diamondNecklace),diamondNecklace)=="trade.valuables","diamond necklace classified to trade.valuables")
check(Filter.classify(Filter.describe(cash),cash)=="trade.currency","cash classified to trade.currency")

-- 4. Themed Kits
local fishingRod = fakeItem({fullType="Base.FishingRod",display="Tool"})
local worm = fakeItem({fullType="Base.Worm",food=true,perishable=true})
local seeds = fakeItem({fullType="Base.TomatoSeed",display="Gardening"})
local spray = fakeItem({fullType="Base.PlantSpray",display="Gardening"})
local needle = fakeItem({fullType="Base.Needle",display="Tool"})
local thread = fakeItem({fullType="Base.Thread",display="Material"})
local wrench = fakeItem({fullType="Base.LugWrench",display="Tool"})
local tirePump = fakeItem({fullType="Base.TirePump",display="Tool"})

check(Filter.classify(Filter.describe(fishingRod),fishingRod)=="kit.fishing","fishing rod classified to kit.fishing")
check(Filter.classify(Filter.describe(worm),worm)=="kit.fishing","worm classified to kit.fishing")
check(Filter.classify(Filter.describe(seeds),seeds)=="kit.farming","seeds classified to kit.farming")
check(Filter.classify(Filter.describe(spray),spray)=="kit.farming","plant spray classified to kit.farming")
check(Filter.classify(Filter.describe(needle),needle)=="kit.tailoring","needle classified to kit.tailoring")
check(Filter.classify(Filter.describe(thread),thread)=="kit.tailoring","thread classified to kit.tailoring")
check(Filter.classify(Filter.describe(wrench),wrench)=="kit.mechanic","lug wrench classified to kit.mechanic")
check(Filter.classify(Filter.describe(tirePump),tirePump)=="kit.mechanic","tire pump classified to kit.mechanic")

-- 5. SortPolicy Kit Priority Test
local kitBox = Filter.new()
kitBox.groups["kit.fishing"]=true

local generalFoodBox = Filter.new()
generalFoodBox.groups["food"]=true

local generalToolBox = Filter.new()
generalToolBox.groups["tools"]=true

check(Filter.matches(kitBox, worm), "fishing kit box accepts worm")
check(not Filter.matches(generalFoodBox, worm), "general food box does not accept worm because classified as kit.fishing")
check(Filter.matches(kitBox, fishingRod), "fishing kit box accepts fishing rod")
check(not Filter.matches(generalToolBox, fishingRod), "general tools box does not accept fishing rod because kit overrides")

print("PASS "..count.." storage categories, kits, and disambiguation assertions succeeded.")
