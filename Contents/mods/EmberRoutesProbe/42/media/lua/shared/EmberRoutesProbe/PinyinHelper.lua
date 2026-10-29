-- PinyinHelper: Initial-letter indexing and pinyin search for Chinese & ASCII terms.
-- Supports both PZ Kahlua (Java UTF-16 character codes) and standard UTF-8 multi-byte Lua runtimes.
local PinyinHelper = {}

local function toCodepoint(c)
    local b1 = c:byte(1)
    if not b1 then return nil end
    if b1 > 255 then
        -- Java UTF-16 character in Kahlua
        return b1
    end
    if b1 < 128 then
        return b1
    elseif b1 >= 224 and b1 < 240 and #c >= 3 then
        local b2 = c:byte(2)
        local b3 = c:byte(3)
        return (b1 - 224) * 4096 + (b2 - 128) * 64 + (b3 - 128)
    elseif b1 >= 192 and b1 < 224 and #c >= 2 then
        local b2 = c:byte(2)
        return (b1 - 192) * 64 + (b2 - 128)
    elseif b1 >= 240 and #c >= 4 then
        local b2 = c:byte(2)
        local b3 = c:byte(3)
        local b4 = c:byte(4)
        return (b1 - 240) * 262144 + (b2 - 128) * 4096 + (b3 - 128) * 64 + (b4 - 128)
    end
    return b1
end

local function nextChar(value, index)
    local code = value:byte(index)
    if not code then return nil, index end
    local length = 1
    if code > 255 then
        if code >= 55296 and code <= 56319 then length = 2 end
    elseif code >= 240 then
        length = 4
    elseif code >= 224 then
        length = 3
    elseif code >= 192 then
        length = 2
    end
    return value:sub(index, index + length - 1), index + length
end

-- Numeric codepoints table (immune to any host compiler/source encoding truncations).
local CODEPOINTS_TABLE = {
    [19997] = "s", -- 丝
    [20013] = "z", -- 中
    [20024] = "w", -- 丸
    [20239] = "f", -- 伏
    [20809] = "g", -- 光
    [20891] = "j", -- 军
    [20892] = "n", -- 农
    [20912] = "b", -- 冰
    [20919] = "l", -- 冷
    [20923] = "d", -- 冻
    [20934] = "z", -- 准
    [20991] = "z", -- 凿
    [20992] = "d", -- 刀
    [21032] = "p", -- 刨
    [21046] = "z", -- 制
    [21058] = "j", -- 剂
    [21073] = "j", -- 剑
    [21098] = "j", -- 剪
    [21106] = "g", -- 割
    [21242] = "s", -- 勺
    [21253] = "b", -- 包
    [21269] = "b", -- 匕
    [21273] = "c", -- 匙
    [21307] = "y", -- 医
    [21402] = "h", -- 厚
    [21407] = "y", -- 原
    [21449] = {"c", "f"}, -- 叉 (cha / fork alias)
    [21494] = "y", -- 叶
    [21654] = "k", -- 咖
    [21857] = "f", -- 啡
    [22120] = "q", -- 器
    [22218] = "n", -- 囊
    [22351] = "h", -- 坏
    [22443] = "d", -- 垫
    [22609] = "s", -- 塑
    [22681] = "q", -- 墙
    [22696] = "m", -- 墨
    [22771] = "k", -- 壳
    [22774] = "h", -- 壶
    [22823] = "d", -- 大
    [22836] = "t", -- 头
    [22841] = "j", -- 夹
    [22871] = "t", -- 套
    [22902] = "n", -- 奶
    [22909] = "h", -- 好
    [23004] = "j", -- 姜
    [23376] = "z", -- 子
    [23478] = "j", -- 家
    [23567] = "x", -- 小
    [23610] = "c", -- 尺
    [24037] = "g", -- 工
    [24067] = "b", -- 布
    [24080] = "z", -- 帐
    [24102] = "d", -- 带
    [24125] = "m", -- 帽
    [24178] = "g", -- 干
    [24202] = "c", -- 床
    [24339] = "g", -- 弓
    [24361] = "n", -- 弩
    [24377] = "d", -- 弹
    [25163] = "s", -- 手
    [25203] = "b", -- 扳
    [25209] = "p", -- 批
    [25296] = "g", -- 拐
    [26009] = "l", -- 料
    [26023] = "f", -- 斧
    [26032] = "x", -- 新
    [26087] = "j", -- 旧
    [26381] = "f", -- 服
    [26408] = "m", -- 木
    [26426] = "j", -- 机
    [26438] = "g", -- 杆
    [26447] = "x", -- 杏
    [26454] = "z", -- 杖
    [26465] = "t", -- 条
    [26479] = "b", -- 杯
    [26495] = "b", -- 板
    [26517] = "z", -- 枕
    [26524] = "g", -- 果
    [26525] = "z", -- 枝
    [26538] = "q", -- 枪
    [26550] = "j", -- 架
    [26592] = "n", -- 柠
    [26609] = "z", -- 柱
    [26612] = "c", -- 柴
    [26641] = "s", -- 树
    [26691] = "t", -- 桃
    [26742] = "t", -- 桶
    [26753] = "l", -- 梁
    [26792] = "l", -- 梨
    [26799] = "t", -- 梯
    [26825] = "m", -- 棉
    [26829] = "g", -- 棍
    [26834] = "b", -- 棒
    [26898] = "j", -- 椒
    [27225] = "c", -- 橙
    [27308] = "m", -- 檬
    [27602] = "d", -- 毒
    [27611] = "m", -- 毛
    [27665] = "m", -- 民
    [27700] = "s", -- 水
    [27744] = "c", -- 池
    [27748] = "t", -- 汤
    [27801] = "s", -- 沙
    [27833] = "y", -- 油
    [27877] = "n", -- 泥
    [27893] = "b", -- 泵
    [28040] = "x", -- 消
    [28201] = "w", -- 温
    [28779] = "h", -- 火
    [28783] = "d", -- 灯
    [28784] = "h", -- 灰
    [28790] = "z", -- 灶
    [28809] = "l", -- 炉
    [28818] = "c", -- 炒
    [28856] = "z", -- 炸
    [28866] = "l", -- 烂
    [28900] = "k", -- 烤
    [28909] = "r", -- 热
    [28938] = "h", -- 焊
    [29006] = "j", -- 煎
    [29028] = "m", -- 煤
    [29038] = "z", -- 煮
    [29087] = "s", -- 熟
    [29255] = "p", -- 片
    [29627] = "b", -- 玻
    [29827] = "l", -- 璃
    [29916] = "g", -- 瓜
    [29926] = "w", -- 瓦
    [29942] = "p", -- 瓶
    [29983] = "s", -- 生
    [30002] = "j", -- 甲
    [30005] = "d", -- 电
    [30333] = "b", -- 白
    [30382] = "p", -- 皮
    [30406] = "p", -- 盆
    [30416] = "y", -- 盐
    [30418] = "h", -- 盒
    [30420] = "k", -- 盔
    [30424] = "p", -- 盘
    [30462] = "d", -- 盾
    [30596] = "m", -- 瞄
    [30683] = "m", -- 矛
    [30701] = "d", -- 短
    [30707] = "s", -- 石
    [30742] = "z", -- 砖
    [30772] = "p", -- 破
    [30871] = "w", -- 碗
    [30872] = "d", -- 碘
    [30897] = "j", -- 碱
    [30899] = "t", -- 碳
    [30952] = "m", -- 磨
    [31383] = "c", -- 窗
    [31508] = "b", -- 笔
    [31614] = "q", -- 签
    [31649] = "g", -- 管
    [31661] = "j", -- 箭
    [31665] = "x", -- 箱
    [31735] = "p", -- 篷
    [31859] = "m", -- 米
    [31895] = "c", -- 粗
    [31918] = "l", -- 粮
    [31934] = "j", -- 精
    [31958] = "t", -- 糖
    [32043] = "z", -- 紫
    [32418] = "h", -- 红
    [32433] = "s", -- 纱
    [32440] = "z", -- 纸
    [32447] = "x", -- 线
    [32454] = "x", -- 细
    [32499] = "s", -- 绳
    [32503] = "b", -- 绷
    [32511] = "l", -- 绿
    [32592] = "g", -- 罐
    [32793] = "p", -- 耙
    [32905] = "r", -- 肉
    [32972] = "b", -- 背
    [33014] = "j", -- 胶
    [33026] = "z", -- 脂
    [33167] = "g", -- 膏
    [33540] = "q", -- 茄
    [33590] = "c", -- 茶
    [33609] = "c", -- 草
    [33647] = "y", -- 药
    [33683] = "m", -- 莓
    [33735] = "g", -- 菇
    [33740] = "j", -- 菌
    [33756] = "c", -- 菜
    [33796] = "t", -- 萄
    [33889] = "p", -- 葡
    [33905] = "c", -- 葱
    [33948] = "s", -- 蒜
    [33976] = "z", -- 蒸
    [34013] = "l", -- 蓝
    [34092] = "s", -- 蔬
    [34121] = "j", -- 蕉
    [34180] = "b", -- 薄
    [34223] = "s", -- 薯
    [34507] = "d", -- 蛋
    [34593] = "l", -- 蜡
    [34746] = "l", -- 螺
    [34915] = "y", -- 衣
    [34955] = "d", -- 袋
    [34972] = "w", -- 袜
    [34987] = "b", -- 被
    [35044] = "k", -- 裤
    [35109] = "r", -- 褥
    [35268] = "g", -- 规
    [35910] = "d", -- 豆
    [36148] = "t", -- 贴
    [36710] = "c", -- 车
    [36718] = "l", -- 轮
    [36724] = "z", -- 轴
    [36731] = "q", -- 轻
    [36771] = "l", -- 辣
    [37202] = "j", -- 酒
    [37233] = "j", -- 酱
    [37240] = "s", -- 酸
    [37259] = "c", -- 醋
    [37325] = "z", -- 重
    [37329] = "j", -- 金
    [38024] = "z", -- 针
    [38025] = "d", -- 钉
    [38050] = "g", -- 钢
    [38053] = "y", -- 钥
    [38057] = "g", -- 钩
    [38067] = "q", -- 钳
    [38075] = "z", -- 钻
    [38081] = "t", -- 铁
    [38085] = "q", -- 铅
    [38108] = "t", -- 铜
    [38109] = "l", -- 铝
    [38130] = "c", -- 铲
    [38134] = "y", -- 银
    [38145] = "s", -- 锁
    [38149] = "g", -- 锅
    [38153] = "c", -- 锉
    [38177] = "x", -- 锡
    [38180] = "c", -- 锤
    [38191] = "j", -- 锯
    [38201] = "q", -- 锹
    [38218] = "n", -- 镊
    [38224] = "g", -- 镐
    [38236] = "j", -- 镜
    [38271] = "c", -- 长
    [38376] = "m", -- 门
    [38400] = "f", -- 阀
    [38754] = "m", -- 面
    [38761] = "g", -- 革
    [38772] = "x", -- 靴
    [38795] = "x", -- 鞋
    [38899] = "y", -- 音
    [39135] = "s", -- 食
    [39184] = {"c", "f"}, -- 餐 (can / fan alias)
    [39277] = "f", -- 饭
    [39292] = "b", -- 饼
    [39318] = "s", -- 首
    [39592] = "g", -- 骨
    [40060] = "y", -- 鱼
    [40614] = "m", -- 麦
    [40635] = "m", -- 麻
    [40644] = "h", -- 黄
    [40657] = "h", -- 黑
}

PinyinHelper.CODEPOINTS_TABLE = CODEPOINTS_TABLE

local memoCache = {}

function PinyinHelper.characters(text)
    local chars = {}
    if not text or text == "" then return chars end
    local index = 1
    local len = #text
    while index <= len do
        local c
        c, index = nextChar(text, index)
        if c and c ~= "" then
            chars[#chars + 1] = c
        else
            break
        end
    end
    return chars
end

function PinyinHelper.charInitials(char)
    local cp = toCodepoint(char)
    if not cp then return nil end
    local py = CODEPOINTS_TABLE[cp]
    if py then
        if type(py) == "table" then return py end
        return { py }
    end
    -- ASCII letter or digit pass-through
    if cp < 128 then
        if (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122) or (cp >= 48 and cp <= 57) then
            local ok, s = pcall(string.char, cp)
            if ok and s then return { string.lower(s) } end
        end
    end
    return nil
end

function PinyinHelper.getInitials(text)
    if not text or text == "" then return {} end
    local cached = memoCache[text]
    if cached then return cached end

    local chars = PinyinHelper.characters(text)
    local charChoices = {}

    for _, c in ipairs(chars) do
        local inits = PinyinHelper.charInitials(c)
        if inits then
            charChoices[#charChoices + 1] = inits
        end
    end

    if #charChoices == 0 then
        memoCache[text] = {}
        return {}
    end

    local combos = {""}
    for _, choices in ipairs(charChoices) do
        local nextCombos = {}
        for _, prefix in ipairs(combos) do
            for _, ch in ipairs(choices) do
                if #nextCombos < 16 then
                    nextCombos[#nextCombos + 1] = prefix .. ch
                end
            end
        end
        combos = nextCombos
    end

    -- Also support particle-skipping acronyms (skipping "制" / 21046)
    local hasSkipChar = false
    local skipChoices = {}
    for _, c in ipairs(chars) do
        local cp = toCodepoint(c)
        if cp == 21046 then -- 制
            hasSkipChar = true
        else
            local inits = PinyinHelper.charInitials(c)
            if inits then
                skipChoices[#skipChoices + 1] = inits
            end
        end
    end

    if hasSkipChar and #skipChoices > 0 then
        local skCombos = {""}
        for _, choices in ipairs(skipChoices) do
            local nextSk = {}
            for _, prefix in ipairs(skCombos) do
                for _, ch in ipairs(choices) do
                    if #nextSk < 16 then
                        nextSk[#nextSk + 1] = prefix .. ch
                    end
                end
            end
            skCombos = nextSk
        end
        for _, s in ipairs(skCombos) do
            combos[#combos + 1] = s
        end
    end

    memoCache[text] = combos
    return combos
end

function PinyinHelper.match(text, query)
    if not query or query == "" then return true end
    if not text or text == "" then return false end
    query = string.lower(query)

    local lowerText = string.lower(text)
    if lowerText:find(query, 1, true) then return true end

    local initialsList = PinyinHelper.getInitials(text)
    for _, initStr in ipairs(initialsList) do
        if initStr:find(query, 1, true) then
            return true
        end
    end

    return false
end

return PinyinHelper
