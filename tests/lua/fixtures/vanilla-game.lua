-- TEST-ONLY helper: resolve the installed vanilla game tree for tests that
-- load original PZ Lua (dofile/require of media/lua files). Never loaded by
-- production. No hardcoded install path: the game root must come from
-- ER_PZ_ROOT, either as the ER_PZ_ROOT environment variable (real Lua) or
-- as an ER_PZ_ROOT global injected by the test harness (Kahlua has no
-- os.getenv). When it is unset or empty, callers SKIP instead of dying on a
-- missing Windows install path.
local Vanilla={}

-- Returns the game root, or nil + a reason when unavailable.
function Vanilla.root()
    if type(ER_PZ_ROOT)=='string' and ER_PZ_ROOT~='' then return ER_PZ_ROOT end
    if os and os.getenv then
        local root=os.getenv('ER_PZ_ROOT')
        if root and root~='' then return root end
    end
    return nil,'ER_PZ_ROOT is not set'
end

-- Returns the <root>/media/lua/shared/ prefix used by native-action tests,
-- or nil + a reason when the game tree is unavailable.
function Vanilla.sharedRoot()
    local root,why=Vanilla.root()
    if not root then return nil,why end
    return root..'/media/lua/shared/'
end

-- Returns the <root>/media/lua/ prefix, or nil + a reason when unavailable.
function Vanilla.luaRoot()
    local root,why=Vanilla.root()
    if not root then return nil,why end
    return root..'/media/lua/'
end

return Vanilla
